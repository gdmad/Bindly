import AVFoundation
import Speech
import os

/// Records the microphone (or, in the E2E build, a file) into Apple's on-device speech recognizer.
///
/// `SpeechTranscriber` is used where it supports the language; Russian and many others are only in
/// `DictationTranscriber`, the engine behind system dictation. Both run entirely on the Mac.
@MainActor
final class SpeechRecorder {
    enum RecorderError: LocalizedError {
        case unsupportedLanguage(String)
        case noMicrophone
        case microphoneDenied

        var errorDescription: String? {
            switch self {
            case .unsupportedLanguage(let id): "Speech recognition does not support \(id)."
            case .noMicrophone: "No microphone is available."
            case .microphoneDenied: "BindAll is not allowed to use the microphone. Allow it in System Settings > Privacy & Security > Microphone."
            }
        }
    }

    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var builder: AsyncStream<AnalyzerInput>.Continuation?
    private var collector: Task<String, Never>?
    /// Buffers and loudness of the current recording, for the indicator and the silent-microphone hint.
    let meter = AudioLevelMeter()
    private var inputName = "none"
    private static let log = Logger(subsystem: "com.evgeny.bindall", category: "voice")

    /// Starts listening. `onText` gets the running transcript (volatile results included).
    /// `onStatus` reports a slow first step, such as downloading the language model.
    /// `onLevel` gets the input level (0...1) about twelve times a second.
    func start(locale: Locale, testAudio: URL?, onStatus: @escaping (String) -> Void,
               onText: @escaping (String) -> Void, onLevel: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        meter.reset()
        if testAudio == nil { try await Self.ensureMicrophone() }
        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        self.builder = builder

        let module: any SpeechModule
        let results: AsyncThrowingStream<(String, Bool), Error>
        if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [],
                                                reportingOptions: [.volatileResults], attributeOptions: [])
            module = transcriber
            results = Self.map(transcriber.results) { (String($0.text.characters), $0.isFinal) }
        } else if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = DictationTranscriber(locale: supported, contentHints: [], transcriptionOptions: [.punctuation],
                                                   reportingOptions: [.volatileResults], attributeOptions: [])
            module = transcriber
            results = Self.map(transcriber.results) { (String($0.text.characters), $0.isFinal) }
        } else {
            throw RecorderError.unsupportedLanguage(locale.identifier)
        }

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            onStatus("Downloading the speech model…")
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw RecorderError.noMicrophone
        }

        collector = Task {
            var final = ""
            var volatile = ""
            do {
                for try await (text, isFinal) in results {
                    if isFinal { final += text; volatile = "" } else { volatile = text }
                    onText((final + volatile).trimmingCharacters(in: .whitespaces))
                }
            } catch {
                Self.log.error("transcription failed: \(error.localizedDescription, privacy: .public)")
            }
            return (final.isEmpty ? volatile : final).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let analyzer = SpeechAnalyzer(modules: [module])
        self.analyzer = analyzer
        if let testAudio {
            inputName = "test audio"
            try Self.feed(file: testAudio, as: format, into: builder, meter: meter)
        } else {
            inputName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "unknown"
            try startMicrophone(format: format, into: builder, onLevel: onLevel)
        }
        try await analyzer.start(inputSequence: stream)
    }

    /// Stops listening and returns the final transcript.
    func finish() async -> String {
        stopMicrophone()
        builder?.finish()
        builder = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        let text = await collector?.value ?? ""
        collector = nil
        let stats = meter.stats
        Self.log.notice("recording: input \(self.inputName, privacy: .public), \(stats.buffers, privacy: .public) buffers, peak \(Int(stats.peakDecibels), privacy: .public) dB, \(text.count, privacy: .public) characters")
        return text
    }

    func cancel() {
        stopMicrophone()
        builder?.finish()
        builder = nil
        let analyzer = self.analyzer
        self.analyzer = nil
        collector?.cancel()
        collector = nil
        Task { await analyzer?.cancelAndFinishNow() }
    }

    // MARK: - Audio

    private func startMicrophone(format: AVAudioFormat, into builder: AsyncStream<AnalyzerInput>.Continuation,
                                 onLevel: @escaping @MainActor @Sendable (Double) -> Void) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw RecorderError.noMicrophone
        }
        let unsafeConverter = converter
        let meter = self.meter
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { buffer, _ in
            if let level = meter.record(buffer) {
                Task { @MainActor in onLevel(level) }
            }
            if let converted = Self.convert(buffer, with: unsafeConverter, to: format) {
                builder.yield(AnalyzerInput(buffer: converted))
            }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    private func stopMicrophone() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private static func feed(file url: URL, as format: AVAudioFormat,
                             into builder: AsyncStream<AnalyzerInput>.Continuation, meter: AudioLevelMeter) throws {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              let converter = AVAudioConverter(from: file.processingFormat, to: format) else { return }
        try file.read(into: buffer)
        _ = meter.record(buffer)
        if let converted = convert(buffer, with: converter, to: format) {
            builder.yield(AnalyzerInput(buffer: converted))
        }
    }

    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter,
                                            to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && out.frameLength > 0 ? out : nil
    }

    private static func map<S: AsyncSequence & Sendable>(_ sequence: S, _ transform: @escaping @Sendable (S.Element) -> (String, Bool))
        -> AsyncThrowingStream<(String, Bool), Error> where S.Element: Sendable {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await element in sequence { continuation.yield(transform(element)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func ensureMicrophone() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .audio) { return }
            throw RecorderError.microphoneDenied
        default:
            throw RecorderError.microphoneDenied
        }
    }
}
