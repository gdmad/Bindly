import Foundation
import AppKit

/// Autocomplete evaluator: simulates typing a prefix of each corpus word (with the previous words as
/// context) and measures how often the correct completion appears in the suggestion list, per engine
/// mode. Used to compare the baseline ranking against the experimental variants (A/B/C).
///
/// Usage: eval_autocomplete <corpusPath> <seedPath> <variant> <cold|warm> [limit]
///   variant: baseline | context | semantic
///   warm:    cold = empty learning store; warm = corpus pre-recorded (words + bigrams/trigrams);
///            picks = warm, and every word is also "picked" on its letters after its trial (online,
///            so a word only gains from a pick when it comes up again), as accepting does in the app
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
        var timesByPrefix: [Int: [Double]] = [:]
        var shortShown = 0, shortRight = 0
        var total = Stats()

        for line in sentences {
            let ws = tokenize(line)
            // Only words with two preceding words: the context the variants are tested on.
            for i in 2..<ws.count {
                let word = ws[i]
                let prev1 = ws[i - 1]
                let prev2 = ws[i - 2]
                for p in prefixes where p < word.count {
                    let partial = String(word.prefix(p))
                    let learnedLimit = mode == .baseline ? limit : max(AutocompleteEngine.reRankPoolLimit, limit)
                    let learned = warm || online ? store.completions(matching: partial, limit: learnedLimit) : []
                    var req = AutocompleteEngine.Request(partial: partial, languages: ["ru"],
                                                         learned: learned, limit: limit, mode: mode)
                    req.contextScorer = contextScorer(store: store, prev1: prev1, prev2: prev2, partial: partial)
                    req.semanticScorer = semanticScorer(context: "\(prev2) \(prev1)", store: store)
                    let started = DispatchTime.now().uptimeNanoseconds
                    let list = AutocompleteEngine.suggestions(request: req)
                    timesByPrefix[p, default: []].append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
                    let rank = list.firstIndex { $0.lowercased() == word }.map { $0 + 1 } ?? 0
                    // At two letters: would the list be shown at all under the "needs support" rule
                    // (the first suggestion is a learned word or has context evidence), and was it right?
                    if p == 2, let first = list.first {
                        let supported = learned.contains { $0.lowercased() == first.lowercased() }
                            || store.contextScore(word: first, prev1: prev1, prev2: prev2) > 0
                        shortShown += supported ? 1 : 0
                        shortRight += supported && rank == 1 ? 1 : 0
                    }
                    statsByPrefix[p, default: Stats()].add(rank: rank)
                    total.add(rank: rank)
                }
                // After all of this word's trials: a pick must not help the same occurrence's next prefix.
                if picks { for p in prefixes where p < word.count { store.recordPick(partial: String(word.prefix(p)), word: word) } }
                if online { store.record(word: word, prev1: prev1, prev2: prev2) }
            }
        }

        print("mode=\(mode.rawValue) store=\(args[3]) limit=\(limit) lang=ru")
        print("prefix  trials  hit@1   hit@3   MRR     absent  avg ms  p95 ms")
        for p in prefixes {
            let times = (timesByPrefix[p] ?? []).sorted()
            let avg = times.isEmpty ? 0 : times.reduce(0, +) / Double(times.count)
            let p95 = times.isEmpty ? 0 : times[min(times.count - 1, Int(Double(times.count) * 0.95))]
            print(String(format: "%d      %@  %6.2f  %6.2f", p, fmt(statsByPrefix[p] ?? Stats()), avg, p95))
        }
        print("all     \(fmt(total))")
        let twoLetter = statsByPrefix[2]?.trials ?? 0
        print(String(format: "2 letters with the support rule: shown %d of %d (%.0f%%), first right when shown %.0f%%",
                     shortShown, twoLetter, 100.0 * Double(shortShown) / Double(max(1, twoLetter)),
                     100.0 * Double(shortRight) / Double(max(1, shortShown))))
    }
}
