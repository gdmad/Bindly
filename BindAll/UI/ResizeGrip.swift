import AppKit
import SwiftUI

/// The corner a window is resized by: it keeps the window's top edge and grows it right and down.
/// The edges resize it too (the panel is resizable); this makes that visible.
struct ResizeGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { GripView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class GripView: NSView {
        private var start: (mouse: NSPoint, frame: NSRect)?

        override var intrinsicContentSize: NSSize { NSSize(width: 14, height: 14) }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.tertiaryLabelColor.setStroke()
            for inset in [3.0, 7.0, 11.0] {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: bounds.maxX - inset, y: bounds.minY + 1))
                path.line(to: NSPoint(x: bounds.maxX - 1, y: bounds.minY + inset))
                path.lineWidth = 1
                path.stroke()
            }
        }

        override func resetCursorRects() { addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all)) }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            (window as? KeyablePanel)?.onManualResize?()
            start = (NSEvent.mouseLocation, window.frame)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, let start else { return }
            let now = NSEvent.mouseLocation
            let min = window.minSize
            let width = max(min.width, start.frame.width + now.x - start.mouse.x)
            let height = max(min.height, start.frame.height - (now.y - start.mouse.y))
            window.setFrame(NSRect(x: start.frame.minX, y: start.frame.maxY - height, width: width, height: height), display: true)
        }

        override func mouseUp(with event: NSEvent) { start = nil }
    }
}
