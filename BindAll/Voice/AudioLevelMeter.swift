import AVFoundation
import os

/// How loud the input is, measured on the audio thread: the indicator's microphone follows it, and it
/// tells a silent or wrong input device apart from "nothing was said".
final class AudioLevelMeter: @unchecked Sendable {
    struct Stats {
        var buffers = 0
        /// Loudest buffer so far, RMS in dBFS; -160 before any sound.
        var peakDecibels: Float = -160
    }

    /// Below this through the whole first moments of a recording, the microphone is taken as silent.
    static let silentDecibels: Float = -60

    private let lock = OSAllocatedUnfairLock(initialState: (stats: Stats(), lastReport: 0.0))

    /// Records one buffer; returns its level (0...1) when the indicator is due an update.
    func record(_ buffer: AVAudioPCMBuffer, now: Double = ProcessInfo.processInfo.systemUptime) -> Double? {
        let decibels = Self.rmsDecibels(buffer)
        return lock.withLock { state in
            state.stats.buffers += 1
            state.stats.peakDecibels = max(state.stats.peakDecibels, decibels)
            guard now - state.lastReport >= 0.08 else { return nil }
            state.lastReport = now
            return Self.level(decibels: decibels)
        }
    }

    var stats: Stats { lock.withLock { $0.stats } }

    func reset() { lock.withLock { $0 = (Stats(), 0) } }

    /// -50 dB and below is still, -10 dB and above is full.
    static func level(decibels: Float) -> Double {
        Double(min(1, max(0, (decibels + 50) / 40)))
    }

    private static func rmsDecibels(_ buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0, let channel = buffer.floatChannelData?[0] else { return -160 }
        var sum: Float = 0
        for i in 0..<frames { sum += channel[i] * channel[i] }
        let rms = (sum / Float(frames)).squareRoot()
        return rms > 0 ? 20 * log10(rms) : -160
    }
}
