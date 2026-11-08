import AppKit
import SwiftUI

/// The small floating list of fixes shown above a problem word.
///
/// Like `AutocompleteOverlay`, this must never take focus -- see `PopupPresenter`. The chrome, the
/// cells, the layouts and the placement all come from `PopupKit`, shared with the autocomplete popup.
@MainActor
final class ProofreadPopover {
    private let presenter = PopupPresenter(ignoresMouseEvents: false, name: "BindAll Fixes") // rows accept hover and click-to-apply
    /// How many fixes the last tile presentation put on its first row (0 = not a tile / even split).
    /// The controller reads it so vertical arrow navigation jumps by the real column count.
    private(set) var lastTileTopCount = 0
    /// Whether the popup went above the word (its usual place): the fixes then list bottom-up, the
    /// first nearest the word, and ↑ is the way in.
    private(set) var placedAbove = true

    /// Shows `issue`'s fixes with `selected` highlighted, placed above `anchor` -- the word's rect in
    /// AppKit screen coordinates. `onHover`/`onAccept` receive the row index the mouse is on.
    func show(issue: TextIssue, selected: Int, softSelection: Bool, position: String, anchor: CGRect,
              layout: PopupLayout, fontSize: CGFloat, onHover: @escaping (Int) -> Void,
              onAccept: @escaping (Int) -> Void, onClose: @escaping () -> Void,
              fixAllCount: Int = 0, onAddWord: (() -> Void)? = nil, onFixAll: @escaping () -> Void = {}) {
        let topCount = layout == .tile
            ? PopupTile.topRowCount(for: issue.replacements, fontSize: fontSize,
                                    near: NSPoint(x: anchor.minX, y: anchor.maxY))
            : 0
        lastTileTopCount = topCount
        func view(bottomUp: Bool) -> FixesPopupView {
            FixesPopupView(title: issue.shortMessage.isEmpty ? issue.message : issue.shortMessage,
                                  kind: issue.kind,
                                  replacements: issue.replacements,
                                  selected: selected,
                                  softSelection: softSelection,
                                  layout: layout,
                                  tileTopCount: topCount,
                                  position: position,
                                  fontSize: fontSize,
                                  onHover: onHover,
                                  onAccept: onAccept,
                                  onClose: onClose, bottomUp: bottomUp,
                                  fixAllCount: fixAllCount, onAddWord: onAddWord, onFixAll: onFixAll)
        }
        let frame = presenter.present(view(bottomUp: placedAbove)) { PopupPlacement.origin(above: anchor, size: $0) }
        let above = frame.minY >= anchor.maxY
        if above != placedAbove {
            placedAbove = above
            presenter.present(view(bottomUp: above)) { PopupPlacement.origin(above: anchor, size: $0) }
        }
    }

    /// A one-line notice (checking, no issues, server error) in the same place as the list.
    func showMessage(_ text: String, anchor: CGRect, fontSize: CGFloat, spinner: Bool = false) {
        lastTileTopCount = 0
        presenter.present(PopupMessageView(text: text, fontSize: fontSize, spinner: spinner)) {
            PopupPlacement.origin(above: anchor, size: $0)
        }
    }

    func hide() {
        presenter.hide()
    }
}
