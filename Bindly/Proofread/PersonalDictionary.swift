import Foundation

/// Words the user taught Bindly ("Add to dictionary"): never flagged as spelling mistakes, in any
/// app, across launches. Matched without regard to case; "ё" and "е" count as the same letter.
enum PersonalDictionary {
    static func normalize(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
    }

    static func set(_ words: [String]) -> Set<String> {
        Set(words.map(normalize).filter { !$0.isEmpty })
    }

    /// Drops spelling issues on a dictionary word; grammar and style issues stay.
    static func filter(_ issues: [TextIssue], words: Set<String>) -> [TextIssue] {
        guard !words.isEmpty else { return issues }
        return issues.filter { $0.kind != .spelling || !words.contains(normalize($0.original)) }
    }

    /// `words` with `word` added once, in the order the user added them.
    static func adding(_ word: String, to words: [String]) -> [String] {
        let key = normalize(word)
        guard !key.isEmpty, !set(words).contains(key) else { return words }
        return words + [word.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))]
    }
}
