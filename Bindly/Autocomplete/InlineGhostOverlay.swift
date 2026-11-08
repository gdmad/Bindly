import AppKit

/// Gray completion text drawn right after the caret, in a click-through panel that never takes
/// focus -- the same kind of window the proofread underlines use.
final class InlineGhostOverlay {
    private var panel: NSPanel?
    private let textView = GhostTextView()

    /// `caretCharacter` is the rect of the character before the caret (AppKit screen coordinates);
    /// the text starts exactly at its right edge. `fontSize` is the field's own when the app reports
    /// it, otherwise derived from the line height.
    func show(_ text: String, after caretCharacter: CGRect, fontSize: CGFloat?, fontName: String?) {
        let size = fontSize ?? max(9, caretCharacter.height * 0.78)
        let font = fontName.flatMap { NSFont(name: $0, size: size) } ?? NSFont.systemFont(ofSize: size)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor])
        textView.string = string
        let textSize = string.size()

        let panel = self.panel ?? makePanel()
        // Centered on the character's line; drawn from x = 0, unlike a label cell's 2 pt inset.
        let rect = NSRect(x: caretCharacter.maxX, y: caretCharacter.midY - textSize.height / 2,
                          width: ceil(textSize.width) + 1, height: ceil(textSize.height))
        let screen = NSScreen.screens.first { $0.frame.contains(rect.origin) } ?? NSScreen.main
        let aligned = screen?.backingAlignedRect(rect, options: .alignAllEdgesNearest) ?? rect.integral
        panel.setFrame(aligned, display: false)
        textView.frame = NSRect(origin: .zero, size: aligned.size)
        textView.needsDisplay = true
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.title = "Bindly Inline"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let content = NSView()
        content.addSubview(textView)
        panel.contentView = content
        self.panel = panel
        return panel
    }
}

/// Draws one attributed line at its origin, with no inset.
private final class GhostTextView: NSView {
    var string = NSAttributedString()

    override func draw(_ dirtyRect: NSRect) {
        string.draw(at: .zero)
    }
}
