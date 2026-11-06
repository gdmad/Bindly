import AppKit
import Carbon.HIToolbox
import os

/// Watches the Push to Talk key on its own thread and reports presses to main.
///
/// The tap is active only so it can keep a custom trigger key (and Esc while recording) out of the
/// app; everything else passes untouched, and the callback only reads a lock-protected snapshot.
final class HoldKeyMonitor: @unchecked Sendable {
    enum Raw { case down, up(shift: Bool), other, escape }

    /// Called on main.
    var onEvent: ((Raw) -> Void)?

    private var lock = os_unfair_lock()
    private var keyValue = PushToTalkKey.rightOption
    private var recordingValue = false
    private var triggerDown = false
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var source: CFRunLoopSource?
    private static let log = Logger(subsystem: "com.evgeny.bindall", category: "voice")

    var key: PushToTalkKey {
        get { locked { keyValue } }
        set { locked { keyValue = newValue } }
    }

    /// While recording, Esc is taken out of the app (it cancels instead).
    var recording: Bool {
        get { locked { recordingValue } }
        set { locked { recordingValue = newValue } }
    }

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<HoldKeyMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            Self.log.error("push to talk tap could not be created")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let loop = CFRunLoopGetCurrent()
            self?.runLoop = loop
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "com.bindall.voice.tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop, let source { CFRunLoopRemoveSource(runLoop, source, .commonModes); CFRunLoopStop(runLoop) }
        tap = nil
        source = nil
        runLoop = nil
    }

    private func locked<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return body()
    }

    private func send(_ raw: Raw) {
        DispatchQueue.main.async { [weak self] in self?.onEvent?(raw) }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let pass = Unmanaged.passUnretained(event)
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let (key, recording, wasDown) = locked { (keyValue, recordingValue, triggerDown) }

        switch key {
        case .rightOption:
            if type == .flagsChanged {
                guard code == kVK_RightOption else { return pass } // Shift and the rest are not "another key"
                let down = flags.contains(.maskAlternate)
                guard down != wasDown else { return pass }
                locked { triggerDown = down }
                send(down ? .down : .up(shift: flags.contains(.maskShift)))
                return pass
            }
        case .shortcut(let config):
            if code == Int(config.keyCode), type == .keyDown || type == .keyUp {
                if type == .keyDown {
                    let m = config.modifiers
                    let matches = flags.contains(.maskCommand) == m.command && flags.contains(.maskAlternate) == m.option
                        && flags.contains(.maskControl) == m.control
                    guard matches || wasDown else { return pass }
                    if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 || wasDown { return nil }
                    locked { triggerDown = true }
                    send(.down)
                } else {
                    guard wasDown else { return pass }
                    locked { triggerDown = false }
                    send(.up(shift: flags.contains(.maskShift)))
                }
                return nil
            }
            if type == .flagsChanged { return pass }
        }

        guard type == .keyDown else { return pass }
        if code == kVK_Escape, recording {
            send(.escape)
            return nil
        }
        if wasDown || recording { send(.other) }
        return pass
    }
}
