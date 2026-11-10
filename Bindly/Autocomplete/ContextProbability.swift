import Foundation

/// The probability of a word after the two preceding words, from one snapshot of the tables that
/// matter for this context: interpolated absolute discounting (a simplified Kneser-Ney) over
/// trigram -> bigram -> unigram, computed separately for the personal and the bundled data and then
/// mixed by how much personal evidence this context has. Built once per lookup under the store's
/// lock, then scores every candidate without it. Pure value type.
struct ContextProbability {
    struct Level {
        let following: [String: Int]
        let total: Double
        let types: Double

        init?(_ following: [String: Int]?) {
            guard let following, !following.isEmpty else { return nil }
            self.following = following
            total = Double(following.values.reduce(0, +))
            types = Double(following.count)
        }
    }

    /// Defaults chosen by a grid on `Tests/ru_eval_chat.txt` and checked on the news and general
    /// sets (`Tests/eval_autocomplete.sh`, env DISCOUNT / PERSONAL_K / PERSONAL_FLOOR / SUFFIX).
    struct Tuning {
        /// Subtracted from every seen count; the freed mass goes to the level below.
        var discount = 0.5
        /// Personal share of the mix: n / (n + personalK), n = personal words seen after `prev1`.
        var personalK = 100.0
        /// Personal share with no or little personal evidence for this context.
        var personalFloor = 0.1
        /// How much the ending the preceding word usually takes ("в" -> "-ом") lifts the bundled
        /// model's bottom level; 0 ignores endings. Saturates: 1 to 1000 measured the same.
        var suffixWeight = 10.0
    }

    let personalTrigram: Level?
    let personalBigram: Level?
    let personalUnigram: (String) -> Double
    let seedTrigram: Level?
    let seedBigram: Level?
    let seedUnigram: (String) -> Double
    /// Endings (last two letters) that followed `prev1` in the corpus.
    var seedSuffix: Level? = nil
    var tuning = Tuning()

    func probability(of word: String) -> Double {
        let w = word.lowercased()
        let personal = interpolate(personalTrigram, interpolate(personalBigram, personalUnigram(w), w), w)
        var bottom = seedUnigram(w)
        if tuning.suffixWeight > 0, let suffix = seedSuffix, w.count > 2 {
            bottom *= 1 + tuning.suffixWeight * Double(suffix.following[String(w.suffix(2))] ?? 0) / suffix.total
        }
        let seed = interpolate(seedTrigram, interpolate(seedBigram, bottom, w), w)
        let n = personalBigram?.total ?? 0
        let share = n > 0 ? max(tuning.personalFloor, n / (n + tuning.personalK)) : tuning.personalFloor
        return share * personal + (1 - share) * seed
    }

    private func interpolate(_ level: Level?, _ lower: Double, _ word: String) -> Double {
        guard let level, level.total > 0 else { return lower }
        let d = tuning.discount
        let c = Double(level.following[word] ?? 0)
        return max(c - d, 0) / level.total + d * level.types / level.total * lower
    }
}
