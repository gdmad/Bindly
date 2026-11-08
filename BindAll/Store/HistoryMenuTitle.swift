import Foundation

/// How a history entry reads in the star's History submenu: one line, short enough for a menu.
enum HistoryMenuTitle {
    static let maxLength = 48
    /// Entries listed in the submenu, newest first.
    static let count = 8

    static func title(for entry: HistoryEntry) -> String {
        let flat = entry.output.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard flat.count > maxLength else { return flat }
        return flat.prefix(maxLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}
