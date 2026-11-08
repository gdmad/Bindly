import AppKit

/// Where a result, preview or prompt window goes: next to the field it is about.
enum PanelPlacement {
    static let gap: CGFloat = 8
    static let inset: CGFloat = 8

    /// Under the field when it fits, otherwise above it, otherwise centered on `window` (or the
    /// screen). Always kept inside the visible area, never pinned to an edge for lack of room.
    static func origin(size: NSSize, near field: CGRect, window: CGRect?) -> NSPoint {
        let probe = NSPoint(x: field.midX, y: field.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(probe) } ?? NSScreen.main
        return origin(size: size, near: field, window: window,
                      visible: screen?.visibleFrame ?? CGRect(origin: .zero, size: size))
    }

    /// The same, for a given visible screen area (AppKit coordinates).
    static func origin(size: NSSize, near field: CGRect, window: CGRect?, visible: CGRect) -> NSPoint {
        let x = min(max(field.minX, visible.minX + inset), visible.maxX - size.width - inset)
        let below = field.minY - gap - size.height
        if below >= visible.minY + inset { return NSPoint(x: x, y: below) }
        let above = field.maxY + gap
        if above + size.height <= visible.maxY - inset { return NSPoint(x: x, y: above) }
        let host = window.map { $0.intersection(visible) }.flatMap { $0.isNull || $0.isEmpty ? nil : $0 } ?? visible
        let center = NSPoint(x: host.midX - size.width / 2, y: host.midY - size.height / 2)
        return NSPoint(x: min(max(center.x, visible.minX + inset), visible.maxX - size.width - inset),
                       y: min(max(center.y, visible.minY + inset), visible.maxY - size.height - inset))
    }

    /// The tallest a window may get on the screen holding `field` before its body scrolls.
    static func maxHeight(near field: CGRect) -> CGFloat {
        let probe = NSPoint(x: field.midX, y: field.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(probe) } ?? NSScreen.main
        return (screen?.visibleFrame.height ?? 800) * 0.6
    }
}
