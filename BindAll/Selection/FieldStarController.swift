import AppKit
import ApplicationServices

/// Shows one violet star: at the end of the selection when there is one, otherwise in the
/// bottom-right corner of the focused text field. Never both. A click opens the actions menu
/// (`onOpen`), which the coordinator builds.
@MainActor
final class FieldStarController {
    struct Config: Equatable {
        var fieldEnabled = true
        var selectionEnabled = true
    }

    var config = Config()
    /// Whether stars may show in the frontmost app (the Proofread app filter).
    var appAllowed: () -> Bool = { true }
    /// Builds and shows the menu for `context` at the star.
    var onOpen: ((StarContext, NSView) -> Void)?

    private let panel = StarPanel()
    private var monitors: [Any] = []
    private var appObserver: NSObjectProtocol?
    private var pending: Task<Void, Never>?
    private var shownKind: String?
    private var shownElement: AXUIElement?
    /// Where the mouse was last released (AppKit coordinates): a selection made with the mouse ends
    /// there, which places the star when the app reports no geometry for the selection.
    private var lastMouseUp: NSPoint?

    private var enabled: Bool { config.fieldEnabled || config.selectionEnabled }

    func apply(_ config: Config) {
        self.config = config
        if enabled { start() } else { stop() }
    }

    private func start() {
        guard monitors.isEmpty else { schedule(); return }
        // Passive monitors: they never delay the events, they only tell us to look again.
        let events: [NSEvent.EventTypeMask] = [.leftMouseUp, .keyUp, .scrollWheel, .keyDown]
        for mask in events {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
                MainActor.assumeIsolated { self?.observed(event) }
            }) {
                monitors.append(monitor)
            }
        }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
        schedule()
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        appObserver = nil
        pending?.cancel()
        hide()
    }

    private func observed(_ event: NSEvent) {
        if event.type == .leftMouseUp { lastMouseUp = NSEvent.mouseLocation }
        switch event.type {
        case .keyDown, .scrollWheel:
            // Typing moves the selection and scrolling moves the field: get out of the way at once.
            hide()
            schedule(delay: .milliseconds(event.type == .scrollWheel ? 450 : 700))
        default:
            schedule()
        }
    }

    /// Looks again once things settle: after a click the app updates its selection a moment later.
    private func schedule(delay: Duration = .milliseconds(300)) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    private func evaluate() {
        guard enabled, appAllowed(),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier,
              case .axField(let target) = ProofreadAX.focus(analyze: false),
              let fieldQuartz = ProofreadAX.frame(of: target.element),
              fieldQuartz.width >= 140, fieldQuartz.height >= 20 else {
            hide()
            return
        }
        let screenHeight = NSScreen.screens.first?.frame.height ?? fieldQuartz.maxY
        let size = StarButton.size
        if target.selection.length > 0, config.selectionEnabled {
            // Below the end of the selection: editors put their own toolbar above it. Without
            // geometry for the selection, where the mouse let go is where it ended.
            let origin: NSPoint
            if let end = selectionEndRect(target, screenHeight: screenHeight) {
                origin = NSPoint(x: end.maxX + 2, y: end.minY - size - 2)
            } else if let mouse = lastMouseUp {
                origin = NSPoint(x: mouse.x + 4, y: mouse.y - size - 4)
            } else {
                let field = UnderlineGeometry.appKitRect(fromQuartz: fieldQuartz, primaryScreenHeight: screenHeight)
                origin = NSPoint(x: field.maxX - size - 6, y: field.minY + 6)
            }
            show(target, kind: "selection", origin: origin, label: "Actions for the selection")
        } else if config.fieldEnabled, target.selection.length == 0, target.isEditable {
            let field = UnderlineGeometry.appKitRect(fromQuartz: fieldQuartz, primaryScreenHeight: screenHeight)
            let origin = NSPoint(x: field.maxX - size - 6, y: field.minY + 6)
            show(target, kind: "field", origin: origin, label: "Actions for this text")
        } else {
            hide()
        }
    }

    private func selectionEndRect(_ target: ProofTarget, screenHeight: CGFloat) -> CGRect? {
        let last = NSRange(location: NSMaxRange(target.selection) - 1, length: 1)
        let appRange = target.offsetMap?.appRange(last) ?? last
        let expected = (target.text as NSString).substring(with: last)
        guard let quartz = ProofreadAX.boundsForRange(appRange, in: target.element, expecting: expected) else { return nil }
        return UnderlineGeometry.appKitRect(fromQuartz: quartz, primaryScreenHeight: screenHeight)
    }

    private func show(_ target: ProofTarget, kind: String, origin: NSPoint, label: String) {
        let context = StarContext(element: target.element, pid: target.pid, text: target.text,
                                  selection: kind == "selection" ? target.selection : NSRange(location: 0, length: 0),
                                  offsetMap: target.offsetMap,
                                  anchor: NSPoint(x: origin.x + StarButton.size / 2, y: origin.y),
                                  isEditable: target.isEditable)
        // Counted once per field and kind, not on every re-show after typing or scrolling.
        let sameField = shownElement.map { CFEqual($0, target.element) } ?? false
        if !(sameField && shownKind == kind) { UsageLog.record(.star, .shown, detail: kind) }
        shownKind = kind
        shownElement = target.element
        panel.show(at: origin, label: label) { [weak self] view in
            UsageLog.record(.star, .accepted, detail: "open:\(kind)")
            self?.onOpen?(context, view)
        }
    }

    /// Animates the star while an action runs; it also stays put through typing until the work ends.
    func setBusy(_ busy: Bool) {
        panel.setBusy(busy)
        if !busy { schedule() }
    }

    /// Leaves `shownKind` / `shownElement` alone: hiding while typing must not make the next show
    /// count as a new one.
    private func hide() {
        guard !panel.activity.busy else { return }
        panel.hide()
    }
}
