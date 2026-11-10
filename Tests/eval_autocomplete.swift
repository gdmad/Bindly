import Foundation
import AppKit

/// Autocomplete evaluator: simulates typing each Russian corpus word letter by letter (with the
/// previous words as context) and measures where the correct completion lands, per engine mode.
///
/// Usage: eval_autocomplete <corpusPath> <variant> <store> [limit] [bigramSeed] [trigramSeed]
///   variant: baseline | context | semantic
///   store:   cold = empty learning store; warm = corpus pre-recorded (has seen every test sentence);
///            online = starts empty and learns as the text goes, as typing does (the fair mode);
///            online-picks = online, plus a pick on the prefix the word would have been accepted on.
/// Reports hit@1/hit@3/MRR on the visible list, inPool (the word is anywhere in the ranked pool --
/// the ceiling for any ranking), lookup time, and KSR (share of letters saved by accepting).
let prefixes = [2, 3, 4, 5]

struct Stats {
    var trials = 0
    var hits1 = 0
    var hits3 = 0
    var mrrSum = 0.0
    var absent = 0 // target not in the returned suggestions

    mutating func add(rank: Int) {
        trials += 1
        if rank == 1 { hits1 += 1 }
        if rank >= 1 && rank <= 3 { hits3 += 1 }
        if rank > 0 { mrrSum += 1.0 / Double(rank) } else { absent += 1 }
    }
}

/// Splits a sentence into lowercased letter words (numbers/apostrophes/hyphens split tokens, same as
/// the app's word terminators).
func tokenize(_ line: String) -> [String] {
    var words: [String] = []
    var current = ""
    for ch in line {
        if ch.isLetter {
            current.append(ch)
        } else if !current.isEmpty {
            words.append(current.lowercased())
            current = ""
        }
    }
    if !current.isEmpty { words.append(current.lowercased()) }
    return words
}

func isCyrillic(_ word: String) -> Bool {
    word.unicodeScalars.allSatisfy { (0x0400...0x04FF).contains($0.value) }
}

/// Context scorer for variant A/B: interpolated trigram -> bigram -> seed -> frequency evidence for
/// the candidate given the two preceding words. nil is never returned in context mode; the store
/// returns 0 for words with no evidence.
let pickWeight = Double(ProcessInfo.processInfo.environment["PICK_WEIGHT"] ?? "") ?? AutocompleteLearningStore.pickWeight

func contextScorer(store: AutocompleteLearningStore, prev1: String, prev2: String, partial: String) -> ((String) -> Double)? {
    { word in pickWeight * store.pickScore(word: word, partial: partial) + store.contextScore(word: word, prev1: prev1, prev2: prev2) }
}

/// Semantic scorer for variant C (as specified: blended with the frequency prior): cosine
/// similarity between the context text and the candidate (both embedded with the on-device Cyrillic
/// `NLContextualEmbedding`), clipped to 0...1, plus the learned-word frequency prior (0...1).
/// Falls back to the frequency prior alone when the model is not ready.
func semanticScorer(context: String, store: AutocompleteLearningStore) -> ((String) -> Double)? {
    { word in
        let sem = SemanticRanker.shared.similarity(context: context, candidate: word) ?? 0
        return max(0, sem) + store.frequencyScore(word: word)
    }
}

func fmt(_ s: Stats) -> String {
    let t = max(1, s.trials)
    return String(format: "%6d  %5.1f%%  %5.1f%%  %6.3f  %6d",
                  s.trials, 100.0 * Double(s.hits1) / Double(t),
                  100.0 * Double(s.hits3) / Double(t), s.mrrSum / Double(t), s.absent)
}

@main
struct EvalMain {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 4 else {
            print("usage: eval_autocomplete <corpusPath> <variant> <cold|warm> [limit] [bigramSeed] [trigramSeed]")
            exit(2)
        }
        let corpusURL = URL(fileURLWithPath: args[1])
        guard let mode = AutocompleteEngine.Mode(rawValue: args[2]) else {
            print("unknown variant \(args[2]); expected baseline|context|semantic")
            exit(2)
        }
        // online / online-picks: the store starts empty and learns as the text goes, as typing does --
        // the only fair test, since warm has already seen every sentence it is asked about.
        let online = args[3].hasPrefix("online")
        let picks = args[3] == "picks" || args[3] == "online-picks"
        let warm = args[3] == "warm" || args[3] == "picks"
        let limit = args.count > 4 ? (Int(args[4]) ?? 5) : 5
        let bigramSeed = args.count > 5 ? URL(fileURLWithPath: args[5])
                                         : URL(fileURLWithPath: "Bindly/Autocomplete/ru_bigrams_ctx.txt")
        let trigramSeed = args.count > 6 && !args[6].isEmpty ? URL(fileURLWithPath: args[6]) : nil
        let poolLimit = max(AutocompleteEngine.reRankPoolLimit, limit)

        guard let corpusText = try? String(contentsOf: corpusURL, encoding: .utf8) else {
            print("cannot read corpus \(corpusURL.path)")
            exit(2)
        }
        let sentences = corpusText.split(separator: "\n")
            .map(String.init)
            .filter { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Isolated learning store: temp file, explicit seeds so the CLI sees the same data the app
        // bundles. The bigram arg feeds the one seed table that serves both next-word and the
        // context-score level; the optional trigram arg adds the rich-data level.
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("bindly-eval-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let store = AutocompleteLearningStore(fileURL: tmpDir.appendingPathComponent("store.json"),
                                              seedURL: bigramSeed, trigramSeedURL: trigramSeed)

        if warm {
            for line in sentences {
                let ws = tokenize(line)
                for (i, w) in ws.enumerated() {
                    let p1 = i >= 1 ? ws[i - 1] : nil
                    let p2 = i >= 2 ? ws[i - 2] : nil
                    store.record(word: w, prev1: p1, prev2: p2)
                    store.record(word: w, prev1: p1, prev2: p2) // second record: count >= minSurfaceCount
                }
            }
        }

        var statsByPrefix: [Int: Stats] = [:]
        var inPoolByPrefix: [Int: Int] = [:]
        var timesByPrefix: [Int: [Double]] = [:]
        var total = Stats()
        // Keystroke savings: every Cyrillic word is typed letter by letter from `m` letters on and
        // accepted as soon as it is first (Tab: 1 key) or, for KSR@3, in the top 3 (arrows + Tab).
        let minPrefixes = [2, 3]
        var letters = 0
        var saved1: [Int: Int] = [:], saved3: [Int: Int] = [:]

        for line in sentences {
            let ws = tokenize(line)
            for i in ws.indices {
                let word = ws[i]
                let prev1 = i >= 1 ? ws[i - 1] : nil
                let prev2 = i >= 2 ? ws[i - 2] : nil
                // Latin words stay as context only: the evaluator measures Russian completion.
                guard isCyrillic(word) else {
                    if online { store.record(word: word, prev1: prev1, prev2: prev2) }
                    continue
                }
                letters += word.count
                var rankAt: [Int: Int] = [:]
                for p in 2..<max(2, word.count) {
                    let partial = String(word.prefix(p))
                    let learned = warm || online ? store.completions(matching: partial, limit: poolLimit) : []
                    // One request at the pool size: in the re-ranking modes the visible list is its prefix.
                    var req = AutocompleteEngine.Request(partial: partial, languages: ["ru"],
                                                         learned: learned, limit: poolLimit, mode: mode)
                    req.contextScorer = contextScorer(store: store, prev1: prev1 ?? "", prev2: prev2 ?? "", partial: partial)
                    req.semanticScorer = semanticScorer(context: [prev2, prev1].compactMap { $0 }.joined(separator: " "), store: store)
                    let started = DispatchTime.now().uptimeNanoseconds
                    let pool = AutocompleteEngine.suggestions(request: req)
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                    let poolRank = pool.firstIndex { $0.lowercased() == word }.map { $0 + 1 } ?? 0
                    let rank = poolRank <= limit ? poolRank : 0
                    rankAt[p] = rank
                    if prefixes.contains(p) {
                        timesByPrefix[p, default: []].append(elapsed)
                        statsByPrefix[p, default: Stats()].add(rank: rank)
                        inPoolByPrefix[p, default: 0] += poolRank > 0 ? 1 : 0
                        total.add(rank: rank)
                    }
                }
                for m in minPrefixes {
                    let accept1 = (m..<max(m, word.count)).first { rankAt[$0] == 1 }
                    saved1[m, default: 0] += accept1.map { word.count - ($0 + 1) } ?? 0
                    let accept3 = (m..<max(m, word.count)).first { (1...3).contains(rankAt[$0] ?? 0) }
                    saved3[m, default: 0] += accept3.map { max(0, word.count - ($0 + rankAt[$0]!)) } ?? 0
                }
                // After all of this word's trials, so a pick never helps the occurrence that made it:
                // the pick is the prefix the word would have been accepted on.
                if picks, let p = (2..<max(2, word.count)).first(where: { rankAt[$0] == 1 }) {
                    store.recordPick(partial: String(word.prefix(p)), word: word)
                }
                if online { store.record(word: word, prev1: prev1, prev2: prev2) }
            }
        }

        print("corpus=\(corpusURL.lastPathComponent) mode=\(mode.rawValue) store=\(args[3]) limit=\(limit)")
        print("prefix  trials  hit@1   hit@3   MRR     absent  inPool  avg ms  p95 ms")
        for p in prefixes {
            let s = statsByPrefix[p] ?? Stats()
            let times = (timesByPrefix[p] ?? []).sorted()
            let avg = times.isEmpty ? 0 : times.reduce(0, +) / Double(times.count)
            let p95 = times.isEmpty ? 0 : times[min(times.count - 1, Int(Double(times.count) * 0.95))]
            let inPool = 100.0 * Double(inPoolByPrefix[p] ?? 0) / Double(max(1, s.trials))
            print(String(format: "%d      %@  %5.1f%%  %6.2f  %6.2f", p, fmt(s), inPool, avg, p95))
        }
        print("all     \(fmt(total))")
        for m in minPrefixes {
            print(String(format: "KSR from %d letters: %.1f%% (first only), %.1f%% (top 3), %d letters",
                         m, 100.0 * Double(saved1[m] ?? 0) / Double(max(1, letters)),
                         100.0 * Double(saved3[m] ?? 0) / Double(max(1, letters)), letters))
        }
    }
}
