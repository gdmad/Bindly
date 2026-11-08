import AppKit

/// An `NSMenuItem` that runs a closure, so menus can be built inline without a target object per item.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("ClosureMenuItem is created in code only")
    }

    @objc private func run() {
        handler()
    }
}
