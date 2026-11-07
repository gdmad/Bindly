import Foundation

/// A triple-clicked line comes with its line break, a double-clicked word sometimes with a space.
/// Engines trim their answers, so the result is put back between the same edges -- otherwise the
/// replaced line joins the next one.
enum EdgeWhitespace {
    static func wrap(_ result: String, like original: String) -> String {
        let core = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else { return result }
        let leading = original.prefix { $0.isWhitespace || $0.isNewline }
        let rest = original.dropFirst(leading.count)
        guard !rest.isEmpty else { return result }
        let trailing = rest.reversed().prefix { $0.isWhitespace || $0.isNewline }.reversed()
        return String(leading) + core + String(trailing)
    }
}
