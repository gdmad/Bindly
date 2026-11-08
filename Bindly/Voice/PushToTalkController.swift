import AppKit
import Carbon.HIToolbox
import os

/// Push to Talk: hold the key, speak, release, and the words land where the caret is -- optionally
/// translated first. Recognition is Apple's, on the Mac (`SpeechRecorder`).
@MainActor
final class PushToTalkController {
    struct Config: Equatable {
        /// Plain dictation on `key`.
        var enabled = false
        var key = PushToTalkKey.rightOption
        /// Dictate and translate on its own key, whether or not plain dictation is on.
        var translateKeyEnabled = false
        var translateKey = PushToTalkKey.rightCommand
        /// `AppLanguages.autoTag` follows the keyboard layout.
        var language = AppLanguages.autoTag
        var translate = false
        var targetLanguage = "en"
        var restoreClipboard = true
        var fontSize: CGFloat = 13
    }

    /// Translates the dictated text into the given language code; supplied by the coordinator.
    var translate: ((String, String) async throws -> String)?
    /// Dictation put into the text without translating (a translation is recorded by `translate`).
    var onDictated: ((String) -> Void)?

    private var config = Config()
    private let monitor = HoldKeyMonitor()
    private var policy = HoldKeyPolicy()
    private let recorder = SpeechRecorder()
    private let presenter = PopupPresenter(ignoresMouseEvents: true, name: "Bindly Voice")
    private let level = VoiceLevel()
    /// Set when the first moments of a recording were silent, so "nothing heard" can say why.
    private var silent = false
    private var tickTimer: Timer?
    private var target: TextInjector.FocusTarget?
    private var anchor = CGRect.zero
    private var session = 0
    private var started = ContinuousClock.now
    /// The key that started the hold: the translate key always translates.
    private var slot = HoldKeyMonitor.Slot.dictate
    private static let log = Logger(subsystem: "com.evgeny.bindly", category: "voice")

    /// Only the E2E build sets this (scripts/e2e.sh): a recording to play instead of the microphone.
    private static let testAudio = UserDefaults.standard.string(forKey: "PushToTalkTestAudio").map(URL.init(fileURLWithPath:))

    init() {
        monitor.onEvent = { [weak self] raw in self?.handle(raw) }
    }

    func configure(_ config: Config) {
        let wasEnabled = self.config.enabled || self.config.translateKeyEnabled
        self.config = config
        let watched = PushToTalkKey.monitored(dictate: config.enabled ? config.key : nil,
                                              translate: config.translateKeyEnabled ? config.translateKey : nil)
        var keys: [HoldKeyMonitor.Slot: PushToTalkKey] = [:]
        keys[.dictate] = watched.dictate
        keys[.translate] = watched.translate
        monitor.keys = keys
        if !keys.isEmpty, AccessibilityPermission.isGranted {
            if !monitor.isRunning { monitor.start() }
        } else if wasEnabled || monitor.isRunning {
            monitor.stop()
            cancel()
        }
    }

    func stop() {
        monitor.stop()
        cancel()
    }

    // MARK: - Keys

    private func handle(_ raw: HoldKeyMonitor.Raw) {
        let now = ProcessInfo.processInfo.systemUptime
        let output: HoldKeyPolicy.Output
        switch raw {
        case .down(let slot):
            self.slot = slot
            output = policy.handle(.keyDown(at: now))
            startTicking()
        case .up(_, let shift):
            stopTicking()
            output = policy.handle(.keyUp(at: now, shift: shift))
        case .other: output = policy.handle(.otherKey)
        case .escape: output = policy.handle(.escape)
        }
        perform(output)
    }

    private func startTicking() {
        stopTicking()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let output = self.policy.handle(.tick(at: ProcessInfo.processInfo.systemUptime))
                if output != .none { self.stopTicking() }
                self.perform(output)
            }
        }
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func perform(_ output: HoldKeyPolicy.Output) {
        switch output {
        case .none: break
        case .start: begin()
        case .finish(let shift): finish(translateFlip: shift)
        case .cancel:
            UsageLog.record(.voice, .dismissed, reason: "cancelled")
            cancel()
        }
    }

    // MARK: - Session

    private func begin() {
        session &+= 1
        let id = session
        started = .now
        target = .capture()
        anchor = caretAnchor()
        monitor.recording = true
        UsageLog.record(.voice, .shown, detail: slot == .translate ? "translateKey" : nil)
        level.value = 0
        silent = false
        show("Listening…", listening: true)
        let locale = Self.locale(for: config.language)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.recorder.start(locale: locale, testAudio: Self.testAudio,
                                              onStatus: { [weak self] status in
                                                  guard self?.session == id else { return }
                                                  self?.show(status, listening: false)
                                              },
                                              onText: { [weak self] text in
                                                  guard let self, self.session == id, self.monitor.recording else { return }
                                                  self.show(text.isEmpty ? "Listening…" : text, listening: true)
                                              },
                                              onLevel: { [weak self] value in
                                                  guard let self, self.session == id else { return }
                                                  self.level.value = value
                                              })
                self.checkForSilence(session: id)
            } catch {
                guard self.session == id else { return }
                UsageLog.record(.voice, .failed, reason: "start")
                self.monitor.recording = false
                self.policy = HoldKeyPolicy()
                self.recorder.cancel()
                self.flash(error.localizedDescription)
            }
        }
    }

    private func finish(translateFlip: Bool) {
        monitor.recording = false
        let id = session
        let translate = (slot == .translate || config.translate) != translateFlip
        let targetLanguage = config.targetLanguage
        show("…", listening: false)
        Task { [weak self] in
            guard let self else { return }
            var text = await self.recorder.finish()
            guard self.session == id else { return }
            guard !text.isEmpty else {
                UsageLog.record(.voice, .dismissed, reason: self.silent ? "silentInput" : "nothingHeard")
                self.flash(self.silent ? Self.silentMessage : "Nothing was heard.")
                return
            }
            if translate, let translator = self.translate {
                self.show("Translating…", listening: false)
                do {
                    text = try await translator(text, targetLanguage)
                } catch {
                    // The dictation must not be lost: it waits on the clipboard.
                    TextInjector.copyToPasteboard(text)
                    UsageLog.record(.voice, .failed, reason: "translate")
                    self.flash("Translation failed: \(error.localizedDescription) The dictated text is on the clipboard.")
                    return
                }
            }
            guard self.session == id else { return }
            self.presenter.hide()
            TextInjector.replaceSelection(with: text, restorePrevious: self.config.restoreClipboard, target: self.target)
            if !translate { self.onDictated?(text) }
            UsageLog.record(.voice, .applied, detail: translate ? "translated" : nil,
                            ms: UsageLog.elapsed(since: self.started))
        }
    }

    private func cancel() {
        session &+= 1
        stopTicking()
        policy = HoldKeyPolicy()
        monitor.recording = false
        recorder.cancel()
        presenter.hide()
    }

    static let silentMessage = "The microphone is silent. Check the input device in System Settings > Sound."

    /// A moment into the recording: no audio at all, or none above the noise floor, means the wrong
    /// or a muted input device -- said now, while the key is still held, not after the release.
    private func checkForSilence(session id: Int) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, self.session == id, self.monitor.recording else { return }
            let stats = self.recorder.meter.stats
            guard stats.buffers == 0 || stats.peakDecibels < AudioLevelMeter.silentDecibels else { return }
            Self.log.notice("silent input: \(stats.buffers, privacy: .public) buffers, peak \(Int(stats.peakDecibels), privacy: .public) dB")
            self.silent = true
            self.show(Self.silentMessage, listening: true)
        }
    }

    // MARK: - Note by the caret

    private func show(_ text: String, listening: Bool) {
        let anchor = self.anchor
        presenter.present(VoiceIndicatorView(text: text, listening: listening, level: level, fontSize: config.fontSize)) {
            PopupPlacement.origin(above: anchor, size: $0)
        }
    }

    private func flash(_ text: String) {
        let id = session
        show(text, listening: false)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.session == id else { return }
            self.presenter.hide()
        }
    }

    private func caretAnchor() -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        if let element = ProofreadAX.focusedElement(),
           let selection = ProofreadAX.selectedRange(of: element),
           let quartz = ProofreadAX.boundsForRange(NSRange(location: max(0, selection.location - 1), length: 1), in: element) {
            return UnderlineGeometry.appKitRect(fromQuartz: quartz, primaryScreenHeight: height)
        }
        let p = NSEvent.mouseLocation
        return CGRect(x: p.x, y: p.y, width: 1, height: 1)
    }

    /// The language to listen for: the setting, or the keyboard layout's.
    static func locale(for setting: String) -> Locale {
        var code = setting
        if setting == AppLanguages.autoTag {
            let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
            let languages = source.flatMap { TISGetInputSourceProperty($0, kTISPropertyInputSourceLanguages) }
                .map { Unmanaged<CFArray>.fromOpaque($0).takeUnretainedValue() as? [String] ?? [] } ?? []
            code = languages.first ?? Locale.current.language.languageCode?.identifier ?? "en"
        }
        switch code {
        case "ru": return Locale(identifier: "ru_RU")
        case "en": return Locale(identifier: "en_US")
        default: return Locale(identifier: code)
        }
    }
}
