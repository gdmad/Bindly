import Carbon.HIToolbox

/// What a key does while the fixes popup is open. Same model as `AutocompleteKeyPolicy`: the popup
/// keeps out of the way of the arrows until you go into its fixes with ↓, so moving the caret,
/// selecting with Shift and switching the input language just work and close it.
enum ProofreadKeyPolicy {
    enum Action: Equatable {
        case passAndClose(reason: String)
        /// Go into the fixes.
        case enter
        case move(dx: Int, dy: Int)
        /// Back out of the fixes; the popup stays.
        case leave
        case apply
        case nextIssue
        case previousIssue
        case close(reason: String)
    }

    static func action(keyCode: Int, command: Bool, control: Bool, option: Bool, shift: Bool,
                       browsing: Bool, atFirst: Bool, layout: PopupLayout) -> Action {
        if command || control || option { return .passAndClose(reason: "modifier") }
        if keyCode == kVK_Tab { return shift ? .previousIssue : .nextIssue }
        if shift { return .passAndClose(reason: "typedOn") }
        let isReturn = keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter
        if isReturn { return .apply }
        guard browsing else {
            switch keyCode {
            case kVK_DownArrow: return .enter
            case kVK_Escape: return .close(reason: "esc")
            case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown:
                return .passAndClose(reason: "navigation")
            default:
                return .passAndClose(reason: "typedOn")
            }
        }
        if keyCode == kVK_Escape { return .leave }
        if let delta = AutocompleteKeyPolicy.delta(for: keyCode, layout: layout) {
            if atFirst, delta.dy < 0 || (layout == .line && delta.dx < 0) { return .leave }
            return .move(dx: delta.dx, dy: delta.dy)
        }
        switch keyCode {
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown:
            return .passAndClose(reason: "navigation")
        default:
            return .passAndClose(reason: "typedOn")
        }
    }
}
