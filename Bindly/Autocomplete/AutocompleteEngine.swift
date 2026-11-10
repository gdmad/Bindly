import AppKit

/// Word suggestions backed by the system spell checker (`NSSpellChecker`), plus a pure helper for
/// extracting the word currently being typed. Used by the autocomplete feature.
enum AutocompleteEngine {
    /// The word being typed immediately to the left of the caret. Letters only; empty when the caret
    /// sits at a non-letter boundary (so nothing is suggested right after a space or punctuation).
    /// `caretUTF16Offset` is an offset into `text`'s UTF-16 view (matches AX selected-range location).
    static func partialWord(in text: String, caretUTF16Offset: Int) -> String {
        let ns = text as NSString
        let caret = max(0, min(caretUTF16Offset, ns.length))
        var start = caret
        while start > 0 {
            guard let scalar = Unicode.Scalar(ns.character(at: start - 1)),
                  CharacterSet.letters.contains(scalar) else { break }
            start -= 1
        }
        return ns.substring(with: NSRange(location: start, length: caret - start))
    }

    /// The up to `count` completed words immediately before the word being typed at
    /// `caretUTF16Offset`, lowercased, most recent first (`[0]` = the word just before the caret).
    /// Non-letter characters split tokens, so the words are the same units the learning store sees.
    /// Empty when there is no completed word before the caret.
    static func precedingWords(in text: String, caretUTF16Offset: Int, count: Int) -> [String] {
        let ns = text as NSString
        let caret = max(0, min(caretUTF16Offset, ns.length))
        var tokens: [String] = []
        var i = caret
        // Skip the partial word currently being typed.
        while i > 0 {
            guard let scalar = Unicode.Scalar(ns.character(at: i - 1)),
                  CharacterSet.letters.contains(scalar) else { break }
            i -= 1
        }
        // Walk further back, collecting completed letter words.
        while i > 0, tokens.count < count {
            while i > 0 {
                guard let scalar = Unicode.Scalar(ns.character(at: i - 1)),
                      !CharacterSet.letters.contains(scalar) else { break }
                i -= 1
            }
            let end = i
            while i > 0 {
                guard let scalar = Unicode.Scalar(ns.character(at: i - 1)),
                      CharacterSet.letters.contains(scalar) else { break }
                i -= 1
            }
            if i < end {
                tokens.append(ns.substring(with: NSRange(location: i, length: end - i)).lowercased())
            }
        }
        return tokens
    }

    /// Words of `text` that extend `prefix` (case-insensitively), nearest to the caret first, the
    /// word being typed excluded -- buffer-word completion. A word keeps its capitals only where the
    /// text never has it in lowercase and it is capitalized somewhere besides a sentence start, or
    /// past its first letter ("Bindly", "LanguageTool"); "Привет" opening a line comes back as "привет".
    static func documentWords(in text: String, caretUTF16Offset: Int, prefix: String, limit: Int) -> [String] {
        let lowerPrefix = prefix.lowercased()
        guard !lowerPrefix.isEmpty, limit > 0 else { return [] }
        let ns = text as NSString
        let caret = max(0, min(caretUTF16Offset, ns.length))
        struct Seen { var distance: Int; var lowercase: Bool; var midSentence: String? }
        var seen: [String: Seen] = [:]
        var i = 0
        var sentenceStart = true
        while i < ns.length {
            guard let scalar = Unicode.Scalar(ns.character(at: i)), CharacterSet.letters.contains(scalar) else {
                if let scalar = Unicode.Scalar(ns.character(at: i)) {
                    if ".!?\n\r".unicodeScalars.contains(scalar) { sentenceStart = true }
                    else if !CharacterSet.whitespaces.contains(scalar) { sentenceStart = false }
                }
                i += 1
                continue
            }
            let start = i
            while i < ns.length, let s = Unicode.Scalar(ns.character(at: i)), CharacterSet.letters.contains(s) { i += 1 }
            let atStart = sentenceStart
            sentenceStart = false
            // The word under the caret is the one being typed.
            if start <= caret && caret <= i { continue }
            let word = ns.substring(with: NSRange(location: start, length: i - start))
            let key = word.lowercased()
            guard key.count > lowerPrefix.count, key.hasPrefix(lowerPrefix) else { continue }
            let distance = i < caret ? caret - i : start - caret
            var entry = seen[key] ?? Seen(distance: distance, lowercase: false, midSentence: nil)
            entry.distance = min(entry.distance, distance)
            // A capital past the first letter (LanguageTool, API) marks a term wherever it stands.
            let innerCapital = word.dropFirst().contains { $0.isUppercase }
            if word == key { entry.lowercase = true } else if !atStart || innerCapital, entry.midSentence == nil { entry.midSentence = word }
            seen[key] = entry
        }
        return seen.sorted { $0.value.distance != $1.value.distance ? $0.value.distance < $1.value.distance : $0.key < $1.key }
            .prefix(limit)
            .map { key, entry in entry.lowercase ? key : (entry.midSentence ?? key) }
    }

    /// True when every letter of `word` is Cyrillic -- the words the bundled Russian data covers.
    static func isCyrillic(_ word: String) -> Bool {
        !word.isEmpty && word.unicodeScalars.allSatisfy { (0x0400...0x04FF).contains($0.value) }
    }

    private static let wordTerminators: Set<Character> = [".", ",", "!", "?", ";", ":",
                                                          ")", "]", "}", "\"", "»", "”", "…"]

    /// True for characters that close the word being typed, so it is complete and worth learning.
    /// Apostrophes, hyphens and digits are deliberately absent: they sit inside a token, and treating
    /// them as boundaries would learn "don" from "don't" or "co" from "co-founder".
    static func isWordTerminator(_ character: Character) -> Bool {
        wordTerminators.contains(character)
    }

    /// Which candidate pool and ranking a `Request` uses. `baseline` reproduces the original
    /// behavior exactly; the other modes gather the same learned + dictionary candidates and re-rank
    /// them with a scorer supplied by the caller (so this file stays free of the learning store and
    /// the embedding framework).
    enum Mode: String, CaseIterable {
        /// Original behavior: learned completions first (frequency order), then dictionary
        /// completions, then spelling guesses. Context is not consulted.
        case baseline
        /// Variant A/B: gather learned + dictionary completions into a larger pool, then rank it with
        /// `contextScorer` (previous-word n-gram evidence + frequency prior). Guesses are not used.
        case context
        /// Variant C: same pool, ranked with `semanticScorer` (context-embedding similarity blended
        /// with the frequency prior). Guesses are not used.
        case semantic
    }

    /// One evaluation of the completion engine. `learned` is the caller's frequency-ordered list of
    /// learned words extending `partial`. The scorer closures are optional: a nil scorer degrades the
    /// re-ranking modes to the pool's natural order (frequency, then dictionary).
    struct Request {
        var partial: String
        var languages: [String]   // BCP-47 codes to query; empty means auto-detect a single language
        var learned: [String]
        var limit: Int
        var mode: Mode = .baseline
        /// Higher is better; nil means no context information (falls back to the pool order).
        var contextScorer: ((String) -> Double)? = nil
        /// Higher is better; nil means semantic ranking is unavailable (falls back to the pool order).
        var semanticScorer: ((String) -> Double)? = nil
        /// Words the preceding words lead to (learned and bundled n-grams), best first. The
        /// re-ranking modes put them in the pool before anything else: a word missing from the pool
        /// cannot be ranked up, and the dictionary alone often misses it on short prefixes.
        var contextCandidates: [String] = []
        /// Words already in the field, nearest to the caret first (as an editor's buffer-word
        /// completion does). They bring names and terms no dictionary has. Pool only: an in-field
        /// bonus in the ranking was measured (0 to 100) and did not help.
        var documentWords: [String] = []
        /// The bundled frequency list's words for the prefix, most frequent first: they fill the
        /// pool after the context, field and learned words, before the system dictionary.
        var lexiconWords: [String] = []
    }

    /// How many pool places each source may take in the re-ranking modes, in gathering order, so
    /// one source cannot crowd the others out; the dictionary fills whatever is left.
    static let contextQuota = 10
    static let documentQuota = 5
    static let learnedQuota = 10
    static let lexiconQuota = 20

    /// How many candidates are gathered before a re-ranking mode scores them. Large enough that the
    /// context/semantic ranking has real choices, small enough that NSSpellChecker never floods the
    /// pipeline (it can return hundreds of entries for short prefixes). Internal so the controller
    /// can size its learned-candidate request to match.
    static let reRankPoolLimit = 30

    /// Baseline convenience: original `suggestions(for:languages:learned:limit:)` behavior.
    static func suggestions(for partial: String, languages: [String], learned: [String], limit: Int) -> [String] {
        suggestions(request: Request(partial: partial, languages: languages, learned: learned, limit: limit))
    }

    /// Up to `request.limit` suggestions for the partial word, per `request.mode`. Each result is
    /// recased to the typed word's case pattern. Main-thread only (NSSpellChecker).
    static func suggestions(request: Request) -> [String] {
        guard !request.partial.isEmpty else { return [] }
        let lower = request.partial.lowercased()
        let limit = max(0, request.limit)
        var out: [String] = []

        func addExtending(_ word: String) {
            guard word.count > request.partial.count, word.lowercased().hasPrefix(lower),
                  !out.contains(where: { $0.lowercased() == word.lowercased() }) else { return }
            out.append(word)
        }
        func addCorrection(_ word: String) {
            guard word.lowercased() != lower,
                  !out.contains(where: { $0.lowercased() == word.lowercased() }) else { return }
            out.append(word)
        }
        let checker = NSSpellChecker.shared
        let range = NSRange(location: 0, length: (request.partial as NSString).length)
        func languages() -> [String] {
            guard request.languages.isEmpty else { return request.languages }
            checker.automaticallyIdentifiesLanguages = true
            return [checker.language()]
        }
        // The dictionary's completions, asked for once per request: the call costs milliseconds, and
        // the re-ranking pool takes them in two parts around the bundled lexicon.
        var dictionary: [String]?
        func fillFromSpellChecker(stopAt: Int, includeGuesses: Bool) {
            if dictionary == nil {
                dictionary = languages().flatMap {
                    checker.completions(forPartialWordRange: range, in: request.partial,
                                        language: $0, inSpellDocumentWithTag: 0) ?? []
                }
            }
            for candidate in dictionary ?? [] {
                guard out.count < stopAt else { return }
                addExtending(candidate)
            }
            guard includeGuesses else { return }
            for lang in languages() {
                for guess in (checker.guesses(forWordRange: range, in: request.partial,
                                              language: lang, inSpellDocumentWithTag: 0) ?? []) {
                    guard out.count < stopAt else { return }
                    addCorrection(guess)
                }
            }
        }

        switch request.mode {
        case .baseline:
            // Original pipeline, preserved exactly: learned first, dictionary, then guesses.
            for word in request.learned {
                addExtending(word)
                if out.count >= limit { break }
            }
            if out.count < limit {
                fillFromSpellChecker(stopAt: limit, includeGuesses: true)
            }

        case .context, .semantic:
            // Gather a pool larger than the visible limit so the re-ranking has real choices.
            let poolLimit = max(reRankPoolLimit, limit)
            func take(_ words: [String], quota: Int) {
                var taken = 0
                for word in words {
                    guard taken < quota, out.count < poolLimit else { break }
                    let before = out.count
                    addExtending(word)
                    if out.count > before { taken += 1 }
                }
            }
            take(request.contextCandidates, quota: contextQuota)
            take(request.documentWords, quota: documentQuota)
            take(request.learned, quota: learnedQuota)
            // The system dictionary goes before the bundled list but leaves it room: on ties the pool
            // order decides, and the dictionary's own order ranked better than corpus frequency.
            if out.count < poolLimit {
                fillFromSpellChecker(stopAt: max(out.count, poolLimit - lexiconQuota), includeGuesses: false)
            }
            take(request.lexiconWords, quota: lexiconQuota)
            if out.count < poolLimit {
                fillFromSpellChecker(stopAt: poolLimit, includeGuesses: false)
            }
            let scorer: (String) -> Double
            switch request.mode {
            case .context: scorer = { request.contextScorer?($0) ?? 0 }
            case .semantic: scorer = { request.semanticScorer?($0) ?? 0 }
            case .baseline: fatalError("unreachable")
            }
            // Stable sort by score descending: ties keep the pool order. Each word is scored once --
            // scoring inside the comparator ran the scorer about ten times per word.
            out = out.enumerated()
                .map { (offset: $0.offset, word: $0.element, score: scorer($0.element)) }
                .sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
                .map(\.word)
        }

        // Recase to the typed word's case pattern, de-duplicating again.
        var result: [String] = []
        for word in out {
            let cased = recased(word, like: request.partial)
            if !result.contains(cased) { result.append(cased) }
        }
        return Array(result.prefix(limit))
    }

    /// Whether the dictionary knows `word`, in any of `languages` (empty = the auto-detected one).
    /// Used by the learned-word review to tell typos from real words. Like the rest of the
    /// `NSSpellChecker` work here, call it off the main thread: it is not cheap, and the review runs
    /// it over the whole learned vocabulary.
    static func isKnownWord(_ word: String, languages: [String]) -> Bool {
        let checker = NSSpellChecker.shared
        let langs: [String]
        if languages.isEmpty {
            checker.automaticallyIdentifiesLanguages = true
            langs = [checker.language()]
        } else {
            langs = languages
        }
        for lang in langs {
            let misspelled = checker.checkSpelling(of: word, startingAt: 0, language: lang,
                                                   wrap: false, inSpellDocumentWithTag: 0,
                                                   wordCount: nil)
            if misspelled.location == NSNotFound { return true }
        }
        return false
    }

    /// Recases `candidate` to match the case pattern of `partial`: ALL CAPS, Capitalized first letter,
    /// or the candidate's own (dictionary) case for lowercase / mixed input.
    static func recased(_ candidate: String, like partial: String) -> String {
        let letters = partial.filter { $0.isLetter }
        guard !letters.isEmpty else { return candidate }
        if letters.count >= 2, letters == letters.uppercased(), letters != letters.lowercased() {
            return candidate.uppercased()
        }
        if let first = partial.first, first.isUppercase {
            return candidate.prefix(1).uppercased() + candidate.dropFirst()
        }
        return candidate
    }
}
