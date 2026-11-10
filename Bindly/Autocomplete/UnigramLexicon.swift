import Foundation

/// A bundled word-frequency list with a prefix index: the words sorted, so every word that starts
/// with a prefix sits in one contiguous range found by binary search. Gives the completion pool the
/// common words the system dictionary leaves out of its first few dozen on short prefixes, and a
/// frequency prior for ranking without context. Immutable after loading, so safe from any thread.
struct UnigramLexicon {
    private let words: [String]
    private let counts: [Int32]
    private let maxLogCount: Double

    var count: Int { words.count }

    init(entries: [(String, Int)]) {
        let sorted = entries.sorted { $0.0 < $1.0 }
        words = sorted.map(\.0)
        counts = sorted.map { Int32(clamping: $0.1) }
        maxLogCount = log(1 + Double(counts.max() ?? 0))
    }

    /// Parses `word \t count` lines (any order); malformed lines are skipped, a missing file is empty.
    init(contentsOf url: URL) {
        var entries: [(String, Int)] = []
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            entries.reserveCapacity(120_000)
            for line in text.split(separator: "\n") {
                let cols = line.split(separator: "\t")
                guard cols.count == 2, let c = Int(cols[1]) else { continue }
                entries.append((String(cols[0]), c))
            }
        }
        self.init(entries: entries)
    }

    /// The most frequent words longer than `prefix` that start with it (case-insensitive), best first.
    func completions(prefix: String, limit: Int) -> [String] {
        let lower = prefix.lowercased()
        guard !lower.isEmpty, limit > 0 else { return [] }
        let range = self.range(of: lower)
        guard !range.isEmpty else { return [] }
        let minLength = lower.count
        return range.filter { words[$0].count > minLength }
            .sorted { counts[$0] != counts[$1] ? counts[$0] > counts[$1] : $0 < $1 }
            .prefix(limit)
            .map { words[$0] }
    }

    /// log-scaled frequency of `word` in 0...1 (1 = the most frequent word), 0 when unknown.
    func frequency(of word: String) -> Double {
        let lower = word.lowercased()
        let i = lowerBound(lower)
        guard i < words.count, words[i] == lower, maxLogCount > 0 else { return 0 }
        return log(1 + Double(counts[i])) / maxLogCount
    }

    private func range(of prefix: String) -> Range<Int> {
        let start = lowerBound(prefix)
        // The words with the prefix are contiguous from `start`; find the first one without it.
        var lo = start, hi = words.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if words[mid].hasPrefix(prefix) { lo = mid + 1 } else { hi = mid }
        }
        return start..<lo
    }

    private func lowerBound(_ key: String) -> Int {
        var lo = 0, hi = words.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if words[mid] < key { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}
