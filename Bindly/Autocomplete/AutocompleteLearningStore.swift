import Foundation
import os

/// Learns the words the user types/accepts and which words tend to follow which, to rank suggestions
/// and predict the next word. Persisted locally; contains only words (never API keys or full text).
///
/// Thread-safe: the autocomplete controller reads it from a background work queue while the Settings
/// management UI touches it from the main thread. All access to the mutable `model` is serialized with
/// `lock`, and disk writes are pushed to a background queue so callers never block on I/O.
final class AutocompleteLearningStore {
    static let shared = AutocompleteLearningStore(seedsInBackground: true)

    /// Guards `model` and the seed tables (assigned once, when they finish loading). Held only for cheap in-memory work; disk I/O
    /// happens off-lock on `ioQueue`.
    private var lock = os_unfair_lock()
    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return body()
    }
    /// Serializes disk writes so concurrent `save()` calls never interleave or block the caller.
    private let ioQueue = DispatchQueue(label: "com.bindly.autocomplete.store.io", qos: .utility)

    private struct Model: Codable {
        var wordCounts: [String: Int] = [:]
        var bigrams: [String: [String: Int]] = [:]   // lowercased prev word -> (next -> count)
        var trigrams: [String: [String: Int]] = [:]  // "w2\tw1" (lowercased) -> (next -> count)

        init() {}
        // Resilient: an older file without trigrams still loads.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            wordCounts = try c.decodeIfPresent([String: Int].self, forKey: .wordCounts) ?? [:]
            bigrams = try c.decodeIfPresent([String: [String: Int]].self, forKey: .bigrams) ?? [:]
            trigrams = try c.decodeIfPresent([String: [String: Int]].self, forKey: .trigrams) ?? [:]
        }
    }

    private static func trigramKey(_ w2: String, _ w1: String) -> String {
        w2.lowercased() + "\t" + w1.lowercased()
    }

    private var model = Model()
    /// Bundled seed bigrams (Russian only, Leipzig news corpus) -- the same table serves both the
    /// final next-word backoff and the context-score level for current-word completion ranking.
    /// A separate Google Books corpus served next-word until it was measured against this one and
    /// dropped: Leipzig already covers 89% of its keys, is 11x wider, and reads as more current
    /// ("я" -> "думаю"/"считаю" rather than "и"/"уже"). One file, loaded once. Read-only.
    private var seedBigrams: [String: [String: Int]] = [:]
    /// Bundled seed trigrams (Russian only, Leipzig news corpus), keyed by `trigramKey(prev2, prev1)`,
    /// used as a stronger context-score level than the seed bigrams. Read-only.
    private var seedTrigrams: [String: [String: Int]] = [:]
    /// Bundled endings after a word ("в" -> "ом" -> count), the same shape as the bigram seed. Read-only.
    private var seedSuffixes: [String: [String: Int]] = [:]
    /// Bundled word frequencies (Russian only): pool candidates. Read-only.
    private var lexicon = UnigramLexicon(entries: [])
    private let fileURL: URL
    /// Pending debounced save; guarded by `lock`.
    private var saveDebounce: DispatchWorkItem?

    private static let log = Logger(subsystem: "com.evgeny.bindly", category: "autocomplete")

    /// `seedsInBackground`: the shared store reads the bundled tables (about half a second) off the
    /// launch path; until they land, suggestions simply lack the seeds. Tests and the evaluator load
    /// them synchronously so the first lookup already sees them.
    init(fileURL: URL? = nil, seedURL: URL? = nil, trigramSeedURL: URL? = nil, unigramSeedURL: URL? = nil,
         suffixSeedURL: URL? = nil, seedsInBackground: Bool = false) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = AppPaths.supportDirectory.appendingPathComponent("autocomplete.json")
        }
        load()
        // Explicit URLs override the bundle lookups so tests/CLI can point at the same data files.
        let bigramURL = seedURL ?? Bundle.main.url(forResource: "ru_bigrams_ctx", withExtension: "txt")
        let trigramURL = trigramSeedURL ?? Bundle.main.url(forResource: "ru_trigrams", withExtension: "txt")
        let unigramURL = unigramSeedURL ?? Bundle.main.url(forResource: "ru_unigrams", withExtension: "txt")
        let suffixURL = suffixSeedURL ?? Bundle.main.url(forResource: "ru_suffixes", withExtension: "txt")
        if seedsInBackground {
            DispatchQueue.global(qos: .utility).async { [self] in
                loadSeeds(bigrams: bigramURL, trigrams: trigramURL, unigrams: unigramURL, suffixes: suffixURL)
            }
        } else {
            loadSeeds(bigrams: bigramURL, trigrams: trigramURL, unigrams: unigramURL, suffixes: suffixURL)
        }
    }

    /// Silent by design elsewhere in this class, but a seed failing to load is otherwise
    /// indistinguishable from "the feature just doesn't work" -- log the outcome either way.
    private func loadSeeds(bigrams: URL?, trigrams: URL?, unigrams: URL?, suffixes: URL?) {
        let started = DispatchTime.now().uptimeNanoseconds
        let bi = bigrams.map(Self.loadBigrams(from:)) ?? [:]
        let tri = trigrams.map(Self.loadTrigrams(from:)) ?? [:]
        let lex = unigrams.map(UnigramLexicon.init(contentsOf:)) ?? UnigramLexicon(entries: [])
        let suf = suffixes.map(Self.loadBigrams(from:)) ?? [:]
        withLock {
            seedSuffixes = suf
            seedBigrams = bi
            seedTrigrams = tri
            lexicon = lex
        }
        let ms = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        if bigrams == nil || trigrams == nil || unigrams == nil {
            Self.log.warning("a bundled autocomplete table is missing; ranking and the pool lose that seed")
        }
        Self.log.info("loaded seeds: \(bi.count) bigram keys, \(tri.count) trigram keys, \(lex.count) words in \(ms) ms")
    }

    /// The most frequent bundled words that extend `prefix`, best first.
    func lexiconCompletions(prefix: String, limit: Int) -> [String] {
        withLock { lexicon }.completions(prefix: prefix, limit: limit)
    }

    /// Parses a bigram seed file (tab-separated: prev, next, count). Missing/empty is fine.
    private static func loadBigrams(from url: URL) -> [String: [String: Int]] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var seed: [String: [String: Int]] = [:]
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: "\t")
            guard cols.count >= 3, let freq = Int(cols[2]) else { continue }
            seed[String(cols[0]), default: [:]][String(cols[1])] = freq
        }
        return seed
    }

    /// Parses a trigram seed file (tab-separated: prev2, prev1, next, count), keyed with the same
    /// `trigramKey` the learned model uses. Missing/empty is fine.
    private static func loadTrigrams(from url: URL) -> [String: [String: Int]] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var seed: [String: [String: Int]] = [:]
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: "\t")
            guard cols.count >= 4, let freq = Int(cols[3]) else { continue }
            seed[Self.trigramKey(String(cols[0]), String(cols[1])), default: [:]][String(cols[2])] = freq
        }
        return seed
    }

    var wordCount: Int { withLock { model.wordCounts.count } }

    /// Records a completed word with up to two preceding words (for bigram + trigram learning).
    /// Learned words are stored lowercased so case variants ("Привет"/"привет") do not split; the
    /// engine recases current-word completions to the typed prefix. (Custom words keep their case.)
    func record(word: String, prev1: String?, prev2: String?) {
        let w = word.lowercased()
        guard w.count >= 2, w.allSatisfy({ $0.isLetter }) else { return }
        withLock {
            model.wordCounts[w, default: 0] += 1
            if let p1 = prev1, !p1.isEmpty {
                model.bigrams[p1.lowercased(), default: [:]][w, default: 0] += 1
                if let p2 = prev2, !p2.isEmpty {
                    model.trigrams[Self.trigramKey(p2, p1), default: [:]][w, default: 0] += 1
                }
            }
        }
        // The vocabulary is unbounded, so the file grows with use; a debounced save keeps a fast
        // typist from re-encoding the whole model on every single word.
        persistSoon()
    }

    /// Words typed/accepted fewer than this many times haven't been confirmed as real words yet
    /// (as opposed to one-off typos) and are excluded from suggestions, though still recorded.
    /// Pinned custom words (weight 1_000_000) are always exempt.
    private let minSurfaceCount = 2
    /// The count a pinned custom word gets: far above anything typed.
    static let pinnedWeight = 1_000_000

    /// Learned words extending `partial` (case-insensitive), most-used first.
    func completions(matching partial: String, limit: Int) -> [String] {
        let lower = partial.lowercased()
        return withLock {
            model.wordCounts
                .filter { $0.key.count > partial.count && $0.key.lowercased().hasPrefix(lower)
                         && $0.value >= minSurfaceCount }
                .sorted { $0.value > $1.value }
                .prefix(limit)
                .map { $0.key }
        }
    }

    /// Words that extend `prefix` and followed these preceding words before, best first: learned
    /// trigram, bundled trigram, learned bigram, bundled bigram -- each table by count. Learned
    /// n-grams need `minSurfaceCount` like every learned suggestion; the bundled ones are pre-vetted.
    func contextCandidates(prev1: String?, prev2: String?, prefix: String, limit: Int) -> [String] {
        let lower = prefix.lowercased()
        guard !lower.isEmpty, limit > 0, let p1 = prev1?.lowercased(), !p1.isEmpty else { return [] }
        let p2 = prev2?.lowercased() ?? ""
        return withLock {
            var out: [String] = []
            func add(_ following: [String: Int]?, minCount: Int) {
                guard let following, out.count < limit else { return }
                let matching = following.filter { $0.value >= minCount && $0.key.count > lower.count && $0.key.hasPrefix(lower) }
                for (word, _) in matching.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }) {
                    if !out.contains(word) { out.append(word) }
                    if out.count >= limit { return }
                }
            }
            if !p2.isEmpty {
                add(model.trigrams[Self.trigramKey(p2, p1)], minCount: minSurfaceCount)
                add(seedTrigrams[Self.trigramKey(p2, p1)], minCount: 1)
            }
            add(model.bigrams[p1], minCount: minSurfaceCount)
            add(seedBigrams[p1], minCount: 1)
            return out
        }
    }

    /// Most likely next words, using a trigram -> bigram backoff. `prev1` is the immediately previous
    /// word; `prev2` the one before it (optional).
    func nextWords(prev1: String, prev2: String?, limit: Int) -> [String] {
        withLock {
            var out: [String] = []
            func add(_ following: [String: Int]?, minCount: Int) {
                guard let following else { return }
                for (word, count) in following.sorted(by: { $0.value > $1.value }) {
                    guard count >= minCount else { continue }
                    if !out.contains(word) { out.append(word) }
                    if out.count >= limit { break }
                }
            }
            if let p2 = prev2, !p2.isEmpty {
                add(model.trigrams[Self.trigramKey(p2, prev1)], minCount: minSurfaceCount)
            }
            if out.count < limit {
                add(model.bigrams[prev1.lowercased()], minCount: minSurfaceCount)
            }
            if out.count < limit {
                add(seedBigrams[prev1.lowercased()], minCount: 1) // bundled seed is pre-vetted, exempt
            }
            return Array(out.prefix(limit))
        }
    }

    /// How likely `word` is after `prev1`/`prev2`, for ranking current-word completions
    /// (`ContextProbability`). Positive for every word; for many candidates use
    /// `contextProbability(prev1:prev2:)` once instead.
    func contextScore(word: String, prev1: String?, prev2: String?) -> Double {
        contextProbability(prev1: prev1, prev2: prev2).probability(of: word)
    }

    /// The tables for this context, for scoring many candidates with one lock (`ContextProbability`).
    /// Pinned custom words count as the most used ordinary word, so their huge weight does not
    /// flatten everyone else's personal frequency.
    func contextProbability(prev1: String?, prev2: String?) -> ContextProbability {
        let p1 = prev1?.lowercased() ?? "", p2 = prev2?.lowercased() ?? ""
        return withLock {
            let triKey = !p1.isEmpty && !p2.isEmpty ? Self.trigramKey(p2, p1) : nil
            let counts = model.wordCounts
            let ordinaryMax = counts.values.filter { $0 < Self.pinnedWeight }.max() ?? 1
            let personalTotal = counts.values.reduce(0.0) { $0 + Double(min($1, ordinaryMax)) }
            return ContextProbability(
                personalTrigram: triKey.flatMap { ContextProbability.Level(model.trigrams[$0]) },
                personalBigram: p1.isEmpty ? nil : ContextProbability.Level(model.bigrams[p1]),
                personalUnigram: { w in
                    guard personalTotal > 0, let c = counts[w] else { return 0 }
                    return Double(min(c, ordinaryMax)) / personalTotal
                },
                seedTrigram: triKey.flatMap { ContextProbability.Level(seedTrigrams[$0]) },
                seedBigram: p1.isEmpty ? nil : ContextProbability.Level(seedBigrams[p1]),
                // Uniform: ordering context-free words by corpus frequency ranked worse than the pool
                // order (measured with the lexicon's counts), so the bundled model stops at bigrams.
                seedUnigram: { _ in 1e-5 },
                seedSuffix: p1.isEmpty ? nil : ContextProbability.Level(seedSuffixes[p1]))
        }
    }

    /// Normalized personal-frequency prior for `word` (0...1 against the most-used learned word).
    /// 0 when the word was never learned. Used by the semantic variant to keep learned vocabulary
    /// ahead of dictionary words that are merely semantically close.
    func frequencyScore(word: String) -> Double {
        let w = word.lowercased()
        return withLock {
            guard let c = model.wordCounts[w] else { return 0 }
            return relative(c, to: model.wordCounts.values.max() ?? c)
        }
    }

    /// Normalizes `count` to the 0...1 range against `max` of its context distribution.
    private func relative(_ count: Int, to max: Int) -> Double {
        guard max > 0 else { return 0 }
        return Double(count) / Double(max)
    }

    /// All learned words, most-used first (for the management UI).
    func entries() -> [(word: String, count: Int)] {
        withLock { model.wordCounts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) } }
    }

    /// Adds a custom word pinned to the top of suggestions (very high weight).
    func add(custom word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1, trimmed.allSatisfy({ $0.isLetter }) else { return }
        let snapshot = withLock { () -> Model in
            model.wordCounts[trimmed] = max(model.wordCounts[trimmed] ?? 0, Self.pinnedWeight)
            return model
        }
        persist(snapshot)
    }

    func remove(word: String) {
        let snapshot = withLock { () -> Model in
            model.wordCounts[word] = nil
            for key in model.bigrams.keys {
                model.bigrams[key]?[word] = nil
                if model.bigrams[key]?.isEmpty == true { model.bigrams[key] = nil }
            }
            for key in model.trigrams.keys {
                model.trigrams[key]?[word] = nil
                if model.trigrams[key]?.isEmpty == true { model.trigrams[key] = nil }
            }
            return model
        }
        persist(snapshot)
    }

    func clear() {
        withLock { model = Model() }
        ioQueue.async { [fileURL] in try? FileManager.default.removeItem(at: fileURL) }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Model.self, from: data) else { return }
        model = decoded
    }

    /// Encodes `snapshot` and writes it atomically off the caller's thread, so learning a word never
    /// blocks typing on disk I/O. Writes are serialized on `ioQueue`.
    private func persist(_ snapshot: Model) {
        ioQueue.async { [fileURL] in
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Schedules a save ~2 s out, coalescing with any save already pending.
    private func persistSoon() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let snapshot = self.withLock { self.model }
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: self.fileURL, options: .atomic)
        }
        withLock {
            saveDebounce?.cancel()
            saveDebounce = work
        }
        ioQueue.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// Writes any pending debounced state synchronously. Call on app termination so the last few
    /// learned words are not lost.
    func flush() {
        let pending = withLock { () -> DispatchWorkItem? in
            defer { saveDebounce = nil }
            return saveDebounce
        }
        guard pending != nil else { return }
        pending?.cancel()
        let snapshot = withLock { model }
        ioQueue.sync { [fileURL] in
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
