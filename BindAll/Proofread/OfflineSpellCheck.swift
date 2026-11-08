import AppKit

/// The macOS spell checker over one paragraph, as `TextIssue`s. Spelling only: its grammar check
/// misses most of what LanguageTool finds, and its Russian is weak (see `OfflineSpelling.similar`).
@MainActor
enum OfflineSpellCheck {
    /// Fix spelling without the server: each word's closest guess, from the end so earlier ranges
    /// stay valid; dictionary words are left alone.
    static func corrected(_ text: String, dictionary: Set<String>) -> String {
        let result = NSMutableString(string: text)
        for issue in issues(in: text, language: nil).reversed() {
            guard let fix = issue.replacements.first,
                  !dictionary.contains(PersonalDictionary.normalize(issue.original)) else { continue }
            result.replaceCharacters(in: issue.range, with: fix)
        }
        return result as String
    }

    static func issues(in text: String, language: String?) -> [TextIssue] {
        let checker = NSSpellChecker.shared
        let ns = text as NSString
        let code = language.map { String($0.prefix { $0 != "-" }) }
            ?? LanguageDetector.detect(text)?.languageCode?.identifier ?? "en"
        let results = checker.check(text, range: NSRange(location: 0, length: ns.length),
                                    types: NSTextCheckingResult.CheckingType.spelling.rawValue,
                                    options: [.orthography: NSOrthography.defaultOrthography(forLanguage: code)],
                                    inSpellDocumentWithTag: 0, orthography: nil, wordCount: nil)
        return results.filter { $0.resultType == .spelling && $0.range.length > 0 }.map { result in
            let word = ns.substring(with: result.range)
            let guesses = checker.guesses(forWordRange: result.range, in: text, language: code, inSpellDocumentWithTag: 0) ?? []
            let beforeStart = max(0, result.range.location - TextIssue.contextSpan)
            let afterEnd = min(ns.length, NSMaxRange(result.range) + TextIssue.contextSpan)
            return TextIssue(
                range: result.range,
                kind: .spelling,
                shortMessage: OfflineSpelling.title,
                message: "LanguageTool cannot be reached, so this was checked on this Mac, for spelling only.",
                replacements: OfflineSpelling.similar(word, guesses),
                ruleId: OfflineSpelling.ruleId,
                source: .spellChecker,
                original: word,
                contextBefore: ns.substring(with: NSRange(location: beforeStart, length: result.range.location - beforeStart)),
                contextAfter: ns.substring(with: NSRange(location: NSMaxRange(result.range), length: afterEnd - NSMaxRange(result.range)))
            )
        }
    }
}
