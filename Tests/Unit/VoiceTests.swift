import AVFoundation
import CoreGraphics
import Foundation

func runVoiceTests() {
    print("HoldKeyPolicy")
    do {
        var p = HoldKeyPolicy()
        check(p.handle(.keyDown(at: 0)) == .none && p.handle(.tick(at: 0.1)) == .none, "nothing happens before the hold time")
        check(p.handle(.tick(at: 0.35)) == .start && p.isRecording, "holding long enough starts recording")
        check(p.handle(.keyUp(at: 2, shift: false)) == .finish(shift: false), "release finishes")

        var tap = HoldKeyPolicy()
        _ = tap.handle(.keyDown(at: 0))
        check(tap.handle(.keyUp(at: 0.1, shift: false)) == .none, "a quick tap does nothing")
        check(tap.handle(.tick(at: 1)) == .none, "and no late start after release")

        var modifier = HoldKeyPolicy()
        _ = modifier.handle(.keyDown(at: 0))
        _ = modifier.handle(.otherKey)
        check(modifier.handle(.tick(at: 1)) == .none, "used as a modifier: never records")
        check(modifier.handle(.keyUp(at: 1.2, shift: false)) == .none, "and its release is ignored")
        check(modifier.handle(.keyDown(at: 2)) == .none && modifier.handle(.tick(at: 2.4)) == .start, "the next hold works again")

        var cancel = HoldKeyPolicy()
        _ = cancel.handle(.keyDown(at: 0)); _ = cancel.handle(.tick(at: 0.5))
        check(cancel.handle(.otherKey) == .cancel, "another key while recording cancels")
        var esc = HoldKeyPolicy()
        _ = esc.handle(.keyDown(at: 0)); _ = esc.handle(.tick(at: 0.5))
        check(esc.handle(.escape) == .cancel, "Esc while recording cancels")
        var shifted = HoldKeyPolicy()
        _ = shifted.handle(.keyDown(at: 0)); _ = shifted.handle(.tick(at: 0.5))
        check(shifted.handle(.keyUp(at: 1, shift: true)) == .finish(shift: true), "Shift at release is reported")
    }

    print("AudioLevelMeter")
    do {
        check(AudioLevelMeter.level(decibels: -80) == 0 && AudioLevelMeter.level(decibels: 0) == 1, "level clamps to 0...1")
        check(abs(AudioLevelMeter.level(decibels: -30) - 0.5) < 1e-6, "-30 dB is half way")
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
        buffer.frameLength = 160
        for i in 0..<160 { buffer.floatChannelData![0][i] = 0.1 }
        let meter = AudioLevelMeter()
        check(meter.record(buffer, now: 1) != nil, "the first buffer reports a level")
        check(meter.record(buffer, now: 1.02) == nil, "reports are throttled")
        let stats = meter.stats
        check(stats.buffers == 2 && abs(stats.peakDecibels + 20) < 0.01, "counts buffers and keeps the peak (0.1 RMS = -20 dB)")
        meter.reset()
        check(meter.stats.buffers == 0 && meter.stats.peakDecibels < AudioLevelMeter.silentDecibels, "reset starts silent")
    }
}
