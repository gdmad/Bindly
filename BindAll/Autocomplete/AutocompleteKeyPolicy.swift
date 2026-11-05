import Carbon.HIToolbox

/// What a key does while a suggestion list is up -- modelled on Safari's address bar and macOS's own
/// inline predictions: the list takes nothing but Tab and Esc until you go into it with ↓, so the
/// arrows, Return and switching the input language keep working on the text as usual.
enum AutocompleteKeyPolicy {
    enum Action: Equatable {
        /// Let the key through; the list stays (Shift+letter: still typing the word).
        case pass
        /// Let the key through and close the list.
        case passAndClose(reason: String)
        case accept
        /// Go into the list (the selection becomes visible and the arrows drive it).
        case enter
        case move(dx: Int, dy: Int)
        /// Back out of the list into the text; the list stays up.
        case leave
        /// Swallow the key and close the list.
        case close(reason: String)
    }

    /// `browsing` is whether the user went into the list. `atFirst` is whether the first item is
    /// selected, so ↑ from it backs out again, as in Safari.
    static func action(keyCode: Int, command: Bool, control: Bool, option: Bool, shift: Bool,
                       browsing: Bool, atFirst: Bool, layout: PopupLayout, acceptReturn: Bool) -> Action {
        if command || control || option { return .passAndClose(reason: "modifier") }
        let isReturn = keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter
        if shift {
            // Shift+Return makes a newline, Shift+arrows select text: the user moved on.
            return isReturn || arrows.contains(keyCode) ? .passAndClose(reason: "navigation") : .pass
        }
        if keyCode == kVK_Tab { return .accept }
        guard browsing else {
            switch keyCode {
            case kVK_DownArrow: return .enter
            case kVK_Escape: return .close(reason: "esc")
            default:
                return navigation.contains(keyCode) || isReturn ? .passAndClose(reason: "navigation")
                                                                 : .passAndClose(reason: "typedOn")
            }
        }
        if isReturn { return acceptReturn ? .accept : .passAndClose(reason: "navigation") }
        if keyCode == kVK_Escape { return .leave }
        if let delta = delta(for: keyCode, layout: layout) {
            if atFirst, delta.dy < 0 || (layout == .line && delta.dx < 0) { return .leave }
            return .move(dx: delta.dx, dy: delta.dy)
        }
        return navigation.contains(keyCode) ? .passAndClose(reason: "navigation") : .passAndClose(reason: "typedOn")
    }

    /// The arrows that move inside the list for each layout; the others move the caret.
    static func delta(for keyCode: Int, layout: PopupLayout) -> (dx: Int, dy: Int)? {
        switch (layout, keyCode) {
        case (.column, kVK_UpArrow), (.tile, kVK_UpArrow): return (0, -1)
        case (.column, kVK_DownArrow), (.tile, kVK_DownArrow): return (0, 1)
        case (.line, kVK_LeftArrow), (.tile, kVK_LeftArrow): return (-1, 0)
        case (.line, kVK_RightArrow), (.tile, kVK_RightArrow): return (1, 0)
        case (.line, kVK_DownArrow): return (1, 0)
        case (.line, kVK_UpArrow): return (-1, 0)
        default: return nil
        }
    }

    private static let arrows: Set<Int> = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow]
    private static let navigation: Set<Int> = arrows.union([kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
                                                            kVK_ForwardDelete])
}
