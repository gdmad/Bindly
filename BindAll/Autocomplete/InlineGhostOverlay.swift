import AppKit

/// Gray completion text drawn right after the caret, in a click-through panel that never takes
/// focus -- the same kind of window the proofread underlines use.
final class InlineGhostOverlay {
    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")

    /// `caretCharacter` is the rect of the character before the caret (AppKit screen coordinates);
    /// the text starts at its right edge on the same baseline. `fontSize` is the field's own when the
    /// app reports it, otherwise derived from the line height.
    func show(_ text: String, after caretCharacter: CGRect, fontSize: CGFloat?, fontName: String?) {
        let size = fontSize ?? max(9, caretCharacter.height * 0.78)
        let font = fontName.flatMap { NSFont(name: $0, size: size) } ?? NSFont.systemFont(ofSize: size)
        label.font = font
        label.textColor = .tertiaryLabelColor
        label.stringValue = text
        label.sizeToFit()

        let panel = self.panel ?? makePanel()
        // Baseline alignment: the character rect's bottom is the line's descent below the baseline.
        let origin = NSPoint(x: caretCharacter.maxX, y: caretCharacter.minY - (label.frame.height - caretCharacter.height) / 2)
        panel.setFrame(NSRect(origin: origin, size: label.frame.size), display: true)
        label.frame.origin = .zero
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.title = "BindAll Inline"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let content = NSView()
        content.addSubview(label)
        panel.contentView = content
        self.panel = panel
        return panel
    }
}
