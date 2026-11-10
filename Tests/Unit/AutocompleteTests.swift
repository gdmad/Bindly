import AVFoundation
import CoreGraphics
import Foundation

func runAutocompleteTests() {
    print("Autocomplete partialWord")
    eq(AutocompleteEngine.partialWord(in: "hello wor", caretUTF16Offset: 9), "wor", "partial mid-typing")
    eq(AutocompleteEngine.partialWord(in: "hello ", caretUTF16Offset: 6), "", "empty right after a space")
    eq(AutocompleteEngine.partialWord(in: "hello.wor", caretUTF16Offset: 9), "wor", "word starts after punctuation")
    eq(AutocompleteEngine.partialWord(in: "appl", caretUTF16Offset: 2), "ap", "uses only text left of the caret")
    eq(AutocompleteEngine.partialWord(in: "café", caretUTF16Offset: 4), "café", "accented letters kept")
    eq(AutocompleteEngine.partialWord(in: "", caretUTF16Offset: 0), "", "empty text")

    print("Autocomplete recased")
    eq(AutocompleteEngine.recased("apple", like: "App"), "Apple", "capitalized partial capitalizes")
    eq(AutocompleteEngine.recased("apple", like: "APP"), "APPLE", "all-caps partial uppercases")
    eq(AutocompleteEngine.recased("apple", like: "app"), "apple", "lowercase keeps dictionary case")
    eq(AutocompleteEngine.recased("iPhone", like: "iph"), "iPhone", "lowercase keeps proper-noun case")

    print("Autocomplete precedingWords")
    eqArr(AutocompleteEngine.precedingWords(in: "hello wor", caretUTF16Offset: 9, count: 2),
          ["hello"], "word before the partial")
    eqArr(AutocompleteEngine.precedingWords(in: "hello world ", caretUTF16Offset: 12, count: 2),
          ["world", "hello"], "two words back after a space")
    eqArr(AutocompleteEngine.precedingWords(in: "я хочу пойд", caretUTF16Offset: 11, count: 2),
          ["хочу", "я"], "russian context, most recent first")
    eqArr(AutocompleteEngine.precedingWords(in: "привет,", caretUTF16Offset: 7, count: 2),
          ["привет"], "comma-terminated word still collected")
    eqArr(AutocompleteEngine.precedingWords(in: "a b c d", caretUTF16Offset: 7, count: 2),
          ["c", "b"], "count limits the walk")
    eqArr(AutocompleteEngine.precedingWords(in: "пойд", caretUTF16Offset: 4, count: 2),
          [], "no context at the start")

    print("Autocomplete context ranking")
    let ctxBase = ["пойдем", "пойду", "пойдешь"]
    let scored = AutocompleteEngine.suggestions(request: .init(
        partial: "пойд", languages: ["ru"], learned: ctxBase, limit: 3,
        mode: .context,
        contextScorer: { w in w == "пойду" ? 100 : 0 }))
    eqArr(Array(scored.prefix(3)), ["пойду", "пойдем", "пойдешь"], "context scorer re-ranks the pool")
    let unscored = AutocompleteEngine.suggestions(request: .init(
        partial: "пойд", languages: ["ru"], learned: ctxBase, limit: 3, mode: .context))
    eqArr(unscored, ["пойдем", "пойду", "пойдешь"], "no scorer keeps the pool order")
    let guessesOff = AutocompleteEngine.suggestions(request: .init(
        partial: "коф", languages: ["ru"], learned: [], limit: 5, mode: .context))
    check(!guessesOff.contains("кафе"), "context mode does not use spelling guesses (коф -> кафе)")


    print("Autocomplete pool sources")
    eqArr(AutocompleteEngine.documentWords(in: "Bindly умеет. Привет, бинарный Bindly при", caretUTF16Offset: 41,
                                           prefix: "би", limit: 5),
          ["бинарный"], "only words with the prefix (Latin Bindly does not start with Cyrillic би)")
    eqArr(AutocompleteEngine.documentWords(in: "проект продукт пр", caretUTF16Offset: 17, prefix: "пр", limit: 5),
          ["продукт", "проект"], "nearest to the caret first, the word being typed left out")
    eqArr(AutocompleteEngine.documentWords(in: "Привет. Я сказал привет и Прага пр", caretUTF16Offset: 34, prefix: "пр", limit: 5),
          ["Прага", "привет"],
          "a capital kept mid-sentence (Прага), dropped when the word is also lowercase (привет)")
    eqArr(AutocompleteEngine.documentWords(in: "Проект готов. пр", caretUTF16Offset: 16, prefix: "пр", limit: 5),
          ["проект"], "a capital only at a sentence start is not a name")
    eqArr(AutocompleteEngine.documentWords(in: "LanguageTool нашёл ошибку lan", caretUTF16Offset: 29, prefix: "lan", limit: 5),
          ["LanguageTool"], "a mixed-case term keeps its case")
    eqArr(AutocompleteEngine.documentWords(in: "привет при", caretUTF16Offset: 10, prefix: "привет", limit: 5),
          [], "a word no longer than the prefix is not a completion")

    let lexicon = UnigramLexicon(entries: [("привет", 50), ("при", 900), ("проект", 300), ("пример", 300),
                                           ("работа", 70), ("ёлка", 5), ("еда", 9)])
    eqArr(lexicon.completions(prefix: "пр", limit: 5), ["при", "пример", "проект", "привет"],
          "most frequent first, ties alphabetical")
    eqArr(lexicon.completions(prefix: "При", limit: 5), ["пример", "привет"], "case-insensitive; the prefix itself is no completion")
    eqArr(lexicon.completions(prefix: "ё", limit: 5), ["ёлка"], "ё is its own letter")
    eqArr(lexicon.completions(prefix: "я", limit: 5), [], "no match past the end")
    eqArr(lexicon.completions(prefix: "", limit: 5), [], "an empty prefix suggests nothing")
    check(lexicon.frequency(of: "при") == 1 && lexicon.frequency(of: "нет") == 0 && lexicon.frequency(of: "еда") > 0,
          "frequency is log-scaled against the top word, 0 when unknown")

    print("Autocomplete isWordTerminator")
    check(AutocompleteEngine.isWordTerminator("."), "period ends a word")
    check(AutocompleteEngine.isWordTerminator(","), "comma ends a word")
    check(AutocompleteEngine.isWordTerminator("!"), "exclamation ends a word")
    check(!AutocompleteEngine.isWordTerminator("'"), "apostrophe is inside a contraction")
    check(!AutocompleteEngine.isWordTerminator("-"), "hyphen is inside a compound word")
    check(!AutocompleteEngine.isWordTerminator("5"), "digit is inside a token")
    check(!AutocompleteEngine.isWordTerminator("a"), "letter is not a boundary")

    // MARK: - Proofread


    print("AutocompleteLearningStore")
    // An isolated store: temp state file plus temp seed files, so this never touches the real learned
    // vocabulary or the bundled seeds, and runs the same under `swiftc` as under the app.
    func makeStore(bigramSeed: [(String, String, Int)] = [], trigramSeed: [(String, String, String, Int)] = []) -> AutocompleteLearningStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bindly-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bigramURL = dir.appendingPathComponent("bigrams.txt")
        let bigramText = bigramSeed.map { "\($0.0)\t\($0.1)\t\($0.2)" }.joined(separator: "\n")
        try! bigramText.write(to: bigramURL, atomically: true, encoding: .utf8)
        let trigramURL = dir.appendingPathComponent("trigrams.txt")
        let trigramText = trigramSeed.map { "\($0.0)\t\($0.1)\t\($0.2)\t\($0.3)" }.joined(separator: "\n")
        try! trigramText.write(to: trigramURL, atomically: true, encoding: .utf8)
        return AutocompleteLearningStore(fileURL: dir.appendingPathComponent("store.json"),
                                         seedURL: bigramURL, trigramSeedURL: trigramURL)
    }

    print("Autocomplete picks")
    do {
        let picks = makeStore(bigramSeed: [], trigramSeed: [])
        picks.recordPick(partial: "пр", word: "привет")
        picks.recordPick(partial: "пр", word: "привет")
        picks.recordPick(partial: "пр", word: "проект")
        check(picks.pickScore(word: "привет", partial: "пр") == 1 && picks.pickScore(word: "проект", partial: "пр") == 0.5,
              "the most picked on these letters scores highest")
        check(picks.completions(matching: "пр", limit: 5).prefix(2) == ["привет", "проект"],
              "picked words lead the learned completions, even before they are frequent")
        check(picks.completions(matching: "при", limit: 5) == ["привет"], "a longer prefix keeps only the words still matching")
        check(picks.pickScore(word: "привет", partial: "приве") > 0, "past four letters the four-letter pick still counts")
        picks.recordPick(partial: "п", word: "привет")
        check(picks.picked(matching: "п").isEmpty, "one letter is not remembered")
        picks.remove(word: "проект")
        check(picks.picked(matching: "пр") == ["привет"], "removing a learned word removes its picks")
        picks.clear()
        check(picks.picked(matching: "пр").isEmpty, "clearing clears the picks")
    }

    print("Autocomplete context candidates")
    do {
        let st = makeStore(bigramSeed: [("в", "городе", 900), ("в", "году", 800), ("в", "гостях", 10)],
                           trigramSeed: [("в", "этом", "году", 500)])
        eqArr(st.contextCandidates(prev1: "этом", prev2: "в", prefix: "го", limit: 5), ["году"], "the trigram's words")
        eqArr(st.contextCandidates(prev1: "в", prev2: nil, prefix: "го", limit: 5), ["городе", "году", "гостях"],
              "the bigram's words by count")
        eqArr(st.contextCandidates(prev1: "в", prev2: nil, prefix: "го", limit: 2), ["городе", "году"], "limited")
        eqArr(st.contextCandidates(prev1: nil, prev2: nil, prefix: "го", limit: 5), [], "no context, no candidates")
        st.record(word: "гараже", prev1: "в", prev2: nil)
        check(!st.contextCandidates(prev1: "в", prev2: nil, prefix: "га", limit: 5).contains("гараже"),
              "a learned pair typed once is not offered yet")
        st.record(word: "гараже", prev1: "в", prev2: nil)
        eqArr(st.contextCandidates(prev1: "в", prev2: nil, prefix: "га", limit: 5), ["гараже"], "typed twice, it is")
        let pooled = AutocompleteEngine.suggestions(request: .init(
            partial: "го", languages: ["ru"], learned: [], limit: 3, mode: .context,
            contextCandidates: ["году"], lexiconWords: ["город"]))
        check(pooled.first == "году", "a context candidate leads the pool even when the dictionary does not offer it")
        check(pooled.contains("город") || pooled.count == 3, "lexicon words join the pool")
    }

    // nextWords: learned trigram beats learned bigram beats the seed, in that order, and the seed is
    // exempt from the surface-count threshold that gates learned pairs.
    let s1 = makeStore(bigramSeed: [("в", "магазин", 500)])
    check(s1.nextWords(prev1: "в", prev2: nil, limit: 5) == ["магазин"],
          "the seed backoff fires when nothing is learned, with no surface-count threshold")
    s1.record(word: "школу", prev1: "в", prev2: nil) // once: below minSurfaceCount
    check(s1.nextWords(prev1: "в", prev2: nil, limit: 5) == ["магазин"],
          "a learned pair typed once does not outrank -- or even join -- the seed yet")
    s1.record(word: "школу", prev1: "в", prev2: nil) // twice: clears minSurfaceCount
    check(s1.nextWords(prev1: "в", prev2: nil, limit: 5) == ["школу", "магазин"],
          "a learned bigram that clears the threshold is offered ahead of the seed")
    s1.record(word: "театр", prev1: "в", prev2: "пошёл")
    s1.record(word: "театр", prev1: "в", prev2: "пошёл")
    check(s1.nextWords(prev1: "в", prev2: "пошёл", limit: 5) == ["театр", "школу", "магазин"],
          "a learned trigram is offered before the bigram backoff, not instead of it")
    check(s1.nextWords(prev1: "в", prev2: "пошёл", limit: 1) == ["театр"], "limit caps the result")
    check(s1.nextWords(prev1: "нигде", prev2: nil, limit: 5).isEmpty, "no evidence anywhere: nothing offered")

    // contextScore: the same precedence, plus every layer is normalized so a huge corpus count cannot
    // drown out a small personal one.
    let s2 = makeStore(bigramSeed: [("в", "магазин", 500), ("в", "школу", 10)],
                       trigramSeed: [("пошёл", "в", "театр", 900)])
    s2.record(word: "магазин", prev1: "в", prev2: nil)
    s2.record(word: "магазин", prev1: "в", prev2: nil) // learned bigram, clears the threshold
    check(s2.contextScore(word: "магазин", prev1: "в", prev2: nil) >
          s2.contextScore(word: "школу", prev1: "в", prev2: nil),
          "a learned bigram outweighs the seed bigram even though the seed count is far larger")
    s2.record(word: "театр", prev1: "в", prev2: "пошёл")
    s2.record(word: "театр", prev1: "в", prev2: "пошёл") // learned trigram
    check(s2.contextScore(word: "театр", prev1: "в", prev2: "пошёл") >
          s2.contextScore(word: "магазин", prev1: "в", prev2: "пошёл"),
          "a learned trigram outweighs a learned bigram")
    check(s2.contextScore(word: "рынок", prev1: "в", prev2: nil) == 0,
          "a word with no evidence anywhere scores zero")
    let s3 = makeStore()
    s3.record(word: "привет", prev1: nil, prev2: nil)
    check(s3.contextScore(word: "привет", prev1: nil, prev2: nil) > 0,
          "personal frequency alone still contributes when there is no context match")

    // record(): the surface filter that keeps one-off typos out of nextWords's evidence.
    let s4 = makeStore()
    s4.record(word: "a", prev1: nil, prev2: nil)
    s4.record(word: "ok3", prev1: nil, prev2: nil)
    s4.record(word: "e-mail", prev1: nil, prev2: nil)
    check(s4.entries().isEmpty, "single-letter, digit-containing and hyphenated words are never learned")
    s4.record(word: "привет", prev1: nil, prev2: nil)
    check(s4.entries().map(\.word) == ["привет"], "an ordinary word is learned")

    print("LearnedWordAudit")
    // A small dictionary stands in for NSSpellChecker.
    let dictionary: Set<String> = ["привет", "спасибо", "hello"]
    let learned: [(word: String, count: Int)] = [
        ("привет", 40),
        ("прывет", 2),       // typo, typed twice -- already being suggested
        ("прифет", 7),       // typo, typed often: still a typo
        ("bindly", 1_000_000), // pinned by hand
        ("ok", 3),           // too short to judge
        ("hello", 12),
    ]
    let suspects = LearnedWordAudit.suspects(in: learned) { dictionary.contains($0) }
    check(suspects.map(\.word) == ["прывет", "прифет"], "only the unknown, unpinned, long-enough words")
    check(suspects.first?.word == "прывет", "least-used first: the safest to drop is at the top")
    check(!suspects.contains { $0.word == "bindly" }, "a pinned word is never a suspect")
    check(!suspects.contains { $0.word == "ok" }, "short words are left alone")
    check(LearnedWordAudit.suspects(in: []) { _ in false }.isEmpty, "no words, no suspects")
    check(LearnedWordAudit.suspects(in: learned) { _ in true }.isEmpty,
          "a dictionary that knows everything reports nothing")
    // Equal counts fall back to alphabetical order, so the list does not reshuffle between passes.
    let tied = LearnedWordAudit.suspects(in: [("ббб", 2), ("ааа", 2)]) { _ in false }
    check(tied.map(\.word) == ["ааа", "ббб"], "equal counts are ordered alphabetically")

    print("AutocompleteInsertion.plan")
    check(AutocompleteInsertion.plan(partial: "при", word: "привет") == .append("вет"),
          "a suggestion continuing the partial only types the remainder")
    check(AutocompleteInsertion.plan(partial: "", word: "hello") == .append("hello"),
          "an empty partial (next-word suggestion) types the whole word, deleting nothing")
    check(AutocompleteInsertion.plan(partial: "hel", word: "hel") == .append(""),
          "the suggestion equal to the partial types nothing")
    check(AutocompleteInsertion.plan(partial: "прив", word: "Привет") == .replace(deleteCount: 4, "Привет"),
          "a recased suggestion (no common prefix by case) deletes and retypes in full")
    check(AutocompleteInsertion.plan(partial: "xyz", word: "hello") == .replace(deleteCount: 3, "hello"),
          "an unrelated suggestion deletes the partial and retypes in full")
    check(AutocompleteInsertion.plan(partial: "hello", word: "hel") == .replace(deleteCount: 5, "hel"),
          "a suggestion shorter than the partial (not a continuation) replaces rather than appending")
    check(AutocompleteInsertion.plan(partial: "a😉b", word: "a😉bad") == .append("ad"),
          "UTF-16 delete count and the appended suffix both stay correct past an emoji")

    print("AutocompleteKeyPolicy")
    func ac(_ key: Int, browsing: Bool = false, atFirst: Bool = true, layout: PopupLayout = .column, ret: Bool = true,
            cmd: Bool = false, ctrl: Bool = false, opt: Bool = false, shift: Bool = false) -> AutocompleteKeyPolicy.Action {
        AutocompleteKeyPolicy.action(keyCode: key, command: cmd, control: ctrl, option: opt, shift: shift,
                                     browsing: browsing, atFirst: atFirst, layout: layout, acceptReturn: ret)
    }
    // Shown, not entered: only Tab, Down and Esc are taken.
    check(ac(48) == .accept, "Tab accepts the first suggestion")
    check(ac(125) == .enter, "Down goes into the list, as in Safari")
    check(ac(53) == .close(reason: "esc"), "Esc closes")
    check(ac(126) == .passAndClose(reason: "navigation") && ac(123) == .passAndClose(reason: "navigation")
          && ac(124) == .passAndClose(reason: "navigation"), "Up/Left/Right move the caret and close the list")
    check(ac(36) == .passAndClose(reason: "navigation"), "Return is not taken before entering the list (it may send the message)")
    check(ac(0, shift: true) == .pass, "Shift+letter keeps typing the word")
    check(ac(36, shift: true) == .passAndClose(reason: "navigation"), "Shift+Return makes a newline and closes")
    check(ac(49, ctrl: true) == .passAndClose(reason: "modifier"), "Ctrl+Space (input language) closes the list")
    check(ac(0) == .passAndClose(reason: "typedOn"), "another key goes to the field and closes")
    // Entered.
    check(ac(125, browsing: true, atFirst: true) == .move(dx: 0, dy: 1), "Down moves in the column")
    check(ac(126, browsing: true, atFirst: true) == .leave, "Up from the first item backs out")
    check(ac(126, browsing: true, atFirst: false) == .move(dx: 0, dy: -1), "Up moves when not on the first")
    check(ac(36, browsing: true) == .accept, "Return accepts inside the list")
    check(ac(36, browsing: true, ret: false) == .passAndClose(reason: "navigation"), "unless Accept with Return is off")
    check(ac(53, browsing: true) == .leave, "Esc backs out of the list")
    check(ac(123, browsing: true) == .passAndClose(reason: "navigation"), "Left in a column moves the caret")
    check(ac(124, browsing: true, layout: .line) == .move(dx: 1, dy: 0), "Right moves in a line")
    check(ac(124, browsing: true, layout: .tile) == .move(dx: 1, dy: 0) && ac(125, browsing: true, layout: .tile) == .move(dx: 0, dy: 1),
          "the tile uses all four arrows")

    print("InlineCompletion")
    check(InlineCompletion.caretAtLineEnd(in: "привет", caret: 6), "the end of the text is a line end")
    check(InlineCompletion.caretAtLineEnd(in: "при\nвет", caret: 3), "before a newline is a line end")
    check(!InlineCompletion.caretAtLineEnd(in: "привет мир", caret: 6), "mid-line is not")
    eq(InlineCompletion.suffix(of: "приветствие", after: "привет") ?? "nil", "ствие", "the rest of the word is drawn")
    eq(InlineCompletion.suffix(of: "Привет", after: "при") ?? "nil", "вет", "case does not matter for the match")
    check(InlineCompletion.suffix(of: "малоко", after: "малак") == nil, "a correction is not a completion: it goes to the list")
    check(InlineCompletion.suffix(of: "мир", after: "мир") == nil, "nothing left to draw")

    print("Key policies above the text")
    check(AutocompleteKeyPolicy.action(keyCode: 126, command: false, control: false, option: false, shift: false,
                                       browsing: false, atFirst: true, layout: .column, acceptReturn: true, opensUpward: true) == .enter,
          "a list above the caret is entered with Up")
    check(AutocompleteKeyPolicy.action(keyCode: 125, command: false, control: false, option: false, shift: false,
                                       browsing: false, atFirst: true, layout: .column, acceptReturn: true, opensUpward: true)
          == .passAndClose(reason: "navigation"), "and Down moves the caret instead")
    check(AutocompleteKeyPolicy.action(keyCode: 126, command: false, control: false, option: false, shift: false,
                                       browsing: true, atFirst: true, layout: .column, acceptReturn: true, opensUpward: true) == .move(dx: 0, dy: 1),
          "inside a list above, Up walks away from the text")
    check(AutocompleteKeyPolicy.action(keyCode: 125, command: false, control: false, option: false, shift: false,
                                       browsing: true, atFirst: true, layout: .column, acceptReturn: true, opensUpward: true) == .leave,
          "and Down from the first item backs out")
    check(ProofreadKeyPolicy.action(keyCode: 126, command: false, control: false, option: false, shift: false,
                                    browsing: false, atFirst: true, layout: .column, opensUpward: true) == .enter,
          "the fixes popup above the word is entered with Up")
    check(ProofreadKeyPolicy.action(keyCode: 125, command: false, control: false, option: false, shift: false,
                                    browsing: false, atFirst: true, layout: .column, opensUpward: true) == .passAndClose(reason: "navigation"),
          "Down moves the caret")
}
