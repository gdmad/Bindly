import SwiftUI

/// One item of either popup. The font weight never changes and the cell never scales, so the panel
/// keeps its size as the selection moves.
struct PopupCell: View {
    let text: String
    let isSelected: Bool
    let fontSize: CGFloat
    /// Column layouts stretch their cells so the selection pill spans the whole row.
    var fillsWidth = false
    /// A quiet selection: what Tab would take before the list is entered with ↓.
    var softSelection = false
    /// A leading symbol, for a cell that is an action rather than a word (proofread's "Skip").
    var systemImage: String?
    /// Secondary text for such an action, so it never reads as one of the fixes.
    var isSecondary = false
    /// False for an icon-only action; `text` then remains its name for VoiceOver.
    var showsTitle = true
    /// What a click on the cell does. Nil for a cell that is not clickable (the autocomplete list is
    /// purely keyboard-driven), which is also what keeps it from being announced as a button.
    var onActivate: (() -> Void)?
    /// Lights up under the pointer on its own, for actions that are not part of the arrow selection
    /// (Add to dictionary, Close, Fix all), in the same color as a selected fix.
    var highlightsOnHover = false
    /// A light fill at rest, so a text action reads as a button (Fix all).
    var showsRestingFill = false

    @State private var hovered = false

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage).accessibilityHidden(true)
            }
        }
        .labelStyle(PopupCellLabelStyle(showsIcon: systemImage != nil, showsTitle: showsTitle))
        .font(.system(size: fontSize))
        .foregroundStyle(foreground)
        .padding(.horizontal, PopupMetrics.cellPaddingH)
        .padding(.vertical, PopupMetrics.cellPaddingV)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: PopupMetrics.cellRadius))
        .contentShape(Rectangle())
        .onHover { inside in if highlightsOnHover { hovered = inside } }
        // A tap gesture rather than a Button: the panel is non-activating and never key, and
        // applying the fix on a click is the popup's main job -- not worth risking on a control
        // whose behaviour in such a panel cannot be checked here. The traits and the action
        // below give assistive tech what a Button would have.
        .onTapGesture { onActivate?() }
        // One element with a name, also when only the icon is drawn (Skip, Close) -- otherwise the
        // icon-only cells dropped out of the accessibility tree altogether.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(traits)
        .accessibilityActions {
            if let onActivate { Button(text, action: onActivate) }
        }
    }

    /// The full selection color: a selected fix, or an action under the pointer.
    private var isLit: Bool { (isSelected && !softSelection) || hovered }

    private var background: AnyShapeStyle {
        if isLit { AnyShapeStyle(Color(nsColor: .selectedContentBackgroundColor)) }
        else if isSelected || showsRestingFill { AnyShapeStyle(.quaternary) }
        else { AnyShapeStyle(.clear) }
    }

    private var foreground: AnyShapeStyle {
        if isLit { AnyShapeStyle(Color(nsColor: .selectedMenuItemTextColor)) }
        else if isSecondary { AnyShapeStyle(.secondary) }
        else { AnyShapeStyle(.primary) }
    }

    private var traits: AccessibilityTraits {
        let selection: AccessibilityTraits = isSelected ? .isSelected : []
        let button: AccessibilityTraits = onActivate == nil ? [] : .isButton
        return selection.union(button)
    }
}

/// Title only for words; icon and title for actions.
private struct PopupCellLabelStyle: LabelStyle {
    let showsIcon: Bool
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: PopupMetrics.inlineSpacing) {
            if showsIcon { configuration.icon }
            if showsTitle { configuration.title }
        }
    }
}
