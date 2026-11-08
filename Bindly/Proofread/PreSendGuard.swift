import AppKit
import os

/// Holds back a chat app's "send" Return while issues are underlined (see `PreSendPolicy`).
///
/// The tap is active (it can swallow Return), so it runs on its own thread like autocomplete's and is
/// enabled only while armed or warning: in a field with no issues, typing never passes through it.
/// The callback only reads a lock-protected state and hands decisions to main.
final class PreSendGuard: @unchecked Sendable {
    /// Called on main.
    var onAction: (@MainActor (PreSendPolicy.Action) -> Void)?

    private var lock = os_unfair_lock()
    private var state = PreSendPolicy.State()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var enabled = false
    private static let log = Logger(subsystem: "com.evgeny.bindly", category: "presend")

    /// From main, or from the tap thread once the tap exists (it is only ever created on main).
    func update(_ change: (inout PreSendPolicy.State) -> Void) {
        os_unfair_lock_lock(&lock)
        change(&state)
        let on = state.armed || state.warning
        os_unfair_lock_unlock(&lock)
        if on, tap == nil, Thread.isMainThread { install() }
        os_unfair_lock_lock(&lock)
        let toggle = tap != nil && on != enabled
        if toggle { enabled = on }
        let port = tap
        os_unfair_lock_unlock(&lock)
        if toggle, let port { CGEvent.tapEnable(tap: port, enable: on) }
    }

    var current: PreSendPolicy.State {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return state
    }

    func stop() {
        update { $0 = PreSendPolicy.State() }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop, let source { CFRunLoopRemoveSource(runLoop, source, .commonModes); CFRunLoopStop(runLoop) }
        tap = nil
        source = nil
        runLoop = nil
        enabled = false
    }

    private func install() {
        guard tap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<PreSendGuard>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                                          callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            Self.log.error("pre-send tap could not be created")
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
            CGEvent.tapEnable(tap: tap, enable: false)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "com.bindly.presend.tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, current.armed || current.warning { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let flags = event.flags
        let action = PreSendPolicy.action(keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                                          command: flags.contains(.maskCommand), shift: flags.contains(.maskShift),
                                          option: flags.contains(.maskAlternate), control: flags.contains(.maskControl),
                                          state: current,
                                          targetPid: pid_t(event.getIntegerValueField(.eventTargetUnixProcessID)))
        switch action {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .warn:
            // Flip to warning here, not on main: a second Return typed before main catches up must send.
            update { $0.warning = true }
        case .send, .passAndDismiss, .dismiss, .review, .fixAll:
            update { $0.warning = false }
        }
        DispatchQueue.main.async { [weak self] in self?.onAction?(action) }
        switch action {
        case .send, .passAndDismiss, .pass: return Unmanaged.passUnretained(event)
        case .warn, .review, .fixAll, .dismiss: return nil
        }
    }
}
