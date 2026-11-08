import Foundation

/// When LanguageTool cannot be reached, spelling is still checked on this Mac. Pure parts here;
/// the checker itself is `OfflineSpellCheck`.
enum OfflineSpelling {
    /// Unreachable or refusing for now: no network, a dead or slow server, rate limiting, a server
    /// error. A wrong URL, a rejected account or a cancelled request is not a reason to go offline.
    static func shouldFallBack(after error: Error) -> Bool {
        if let url = error as? URLError { return url.code != .cancelled && url.code != .unsupportedURL && url.code != .badURL }
        if case EngineError.server(let status, _) = error { return status == 429 || status >= 500 }
        return false
    }

    /// macOS's guesses, kept only when they look like the word: its Russian guesses are often far
    /// off ("Прувет" -> "Прусте"), and a wrong fix offered with confidence is worse than none.
    static func similar(_ word: String, _ guesses: [String], limit: Int = 3) -> [String] {
        let w = Array(word.lowercased())
        let scored = guesses.map { ($0, distance(w, Array($0.lowercased()))) }
            .filter { $0.1 <= (w.count <= 4 ? 1 : 2) }
        // Only the closest ones: a one-letter slip beats a guess that also happens to be near.
        guard let best = scored.map(\.1).min() else { return [] }
        return scored.filter { $0.1 == best }.prefix(limit).map(\.0)
    }

    static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    static let ruleId = "OFFLINE_SPELLING"
    static let title = "Offline: spelling only"
}
