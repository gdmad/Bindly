import Foundation

/// Word-level differences between the text before and after an action, for the preview: what was
/// kept, what was added and what was removed, in reading order.
enum TextDiff {
    enum Part: Equatable {
        case same(String)
        case added(String)
        case removed(String)
    }

    /// Longest common subsequence over tokens (words with the whitespace after them), so the
    /// whitespace stays attached and re-joining the parts reproduces either text exactly.
    static func words(old: String, new: String) -> [Part] {
        let a = tokens(old), b = tokens(new)
        // Cap the table: beyond this a preview is better as plain before/after than as a diff.
        guard a.count * b.count <= 400_000 else { return [.removed(old), .added(new)].filter(\.isNotEmpty) }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var parts: [Part] = []
        var i = 0, j = 0
        func push(_ part: Part) {
            switch (parts.last, part) {
            case (.same(let x)?, .same(let y)): parts[parts.count - 1] = .same(x + y)
            case (.added(let x)?, .added(let y)): parts[parts.count - 1] = .added(x + y)
            case (.removed(let x)?, .removed(let y)): parts[parts.count - 1] = .removed(x + y)
            default: parts.append(part)
            }
        }
        while i < a.count, j < b.count {
            if a[i] == b[j] { push(.same(a[i])); i += 1; j += 1 }
            else if table[i + 1][j] >= table[i][j + 1] { push(.removed(a[i])); i += 1 }
            else { push(.added(b[j])); j += 1 }
        }
        while i < a.count { push(.removed(a[i])); i += 1 }
        while j < b.count { push(.added(b[j])); j += 1 }
        return parts
    }

    /// Words together with the whitespace that follows them; leading whitespace is its own token.
    static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inSpace = false
        for character in text {
            let space = character.isWhitespace
            if !current.isEmpty, inSpace, !space {
                out.append(current)
                current = ""
            }
            current.append(character)
            inSpace = space
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// How much of the text the change touches, 0...1, by characters: kept text counts on both sides.
    static func changedShare(_ parts: [Part]) -> Double {
        var kept = 0, changed = 0
        for part in parts {
            switch part {
            case .same(let s): kept += s.count * 2
            case .added(let s), .removed(let s): changed += s.count
            }
        }
        return kept + changed == 0 ? 0 : Double(changed) / Double(kept + changed)
    }

    static func hasChanges(_ parts: [Part]) -> Bool {
        parts.contains { if case .same = $0 { false } else { true } }
    }
}

private extension TextDiff.Part {
    var isNotEmpty: Bool {
        switch self {
        case .same(let s), .added(let s), .removed(let s): !s.isEmpty
        }
    }
}
