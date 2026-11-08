import AVFoundation
import CoreGraphics
import Foundation

func runProofreadTests() {
    print("LanguageTool applyMatches")
    func ltMatch(_ offset: Int, _ length: Int, _ replacement: String) -> [String: Any] {
        ["offset": offset, "length": length, "replacements": [["value": replacement]]]
    }
    eq(LanguageToolEngine.applyMatches([ltMatch(0, 3, "the")], to: "teh cat"), "the cat", "single replacement")
    eq(LanguageToolEngine.applyMatches([ltMatch(0, 3, "the"), ltMatch(4, 3, "the")], to: "teh teh"),
       "the the", "two replacements applied right-to-left")
    eq(LanguageToolEngine.applyMatches([], to: "no change"), "no change", "no matches keeps text")
    eq(LanguageToolEngine.applyMatches([ltMatch(0, 6, "Mishka"), ltMatch(7, 3, "the")], to: "Mishko teh cat",
                                       skipping: PersonalDictionary.set(["mishko"])),
       "Mishko the cat", "a dictionary word is not corrected, the rest is")
    eq(LanguageToolEngine.applyMatches([["offset": 0, "length": 3]], to: "teh cat"),
       "teh cat", "match without replacements is skipped")
    eq(LanguageToolEngine.applyMatches([ltMatch(100, 3, "x")], to: "short"),
       "short", "out-of-range match is ignored")

    print("LanguageToolEngine Equatable")
    // The proofread provider reconfigures only when the engine actually changes; a token-only change
    // must count, so equality has to include the credentials, not just the URL.
    let engA = LanguageToolEngine(baseURL: "u", username: "me", apiKey: "k1", language: "ru")
    let engSame = LanguageToolEngine(baseURL: "u", username: "me", apiKey: "k1", language: "ru")
    let engToken = LanguageToolEngine(baseURL: "u", username: "me", apiKey: "k2", language: "ru")
    check(engA == engSame, "identical engines are equal")
    check(engA != engToken, "a token-only change makes engines unequal")

    print("LanguageToolEngine.parseMatches")
    let ltJSON = """
    {"matches": [
      {"offset": 5, "length": 3, "message": "Spelling mistake", "shortMessage": "Spelling",
       "replacements": [{"value": "the"}, {"value": "thee"}],
       "rule": {"id": "MORFOLOGIK_RULE", "issueType": "misspelling", "category": {"id": "TYPOS"}}},
      {"offset": 20, "length": 2, "message": "No replacement offered", "replacements": [],
       "rule": {"id": "STYLE_X", "issueType": "style", "category": {"id": "STYLE"}}},
      {"offset": -1, "length": 4, "message": "malformed"},
      {"length": 4, "message": "no offset"}
    ]}
    """
    let ltMatches = try! LanguageToolEngine.parseMatches(Data(ltJSON.utf8))
    check(ltMatches.count == 2, "malformed matches are dropped (got \(ltMatches.count))")
    check(ltMatches[0].replacements == ["the", "thee"], "replacements parsed in order")
    eq(ltMatches[0].ruleId ?? "", "MORFOLOGIK_RULE", "rule id parsed")
    eq(ltMatches[0].categoryId ?? "", "TYPOS", "category id parsed")
    eq(ltMatches[0].shortMessage, "Spelling", "short message parsed")
    check(ltMatches[1].replacements.isEmpty, "match without replacements is kept")

    print("LanguageToolEngine.kind")
    check(LanguageToolEngine.kind(for: ltMatches[0]) == .spelling, "TYPOS category → spelling")
    check(LanguageToolEngine.kind(for: ltMatches[1]) == .style, "style issueType → style")
    check(LanguageToolEngine.kind(for: LTMatch(offset: 0, length: 1, message: "", shortMessage: "",
                                               replacements: [], ruleId: nil, issueType: "whitespace",
                                               categoryId: "TYPOGRAPHY")) == .punctuation,
          "whitespace issueType → punctuation")
    check(LanguageToolEngine.kind(for: LTMatch(offset: 0, length: 1, message: "", shortMessage: "",
                                               replacements: [], ruleId: nil, issueType: nil,
                                               categoryId: nil)) == .grammar,
          "unknown issueType → grammar")

    print("LanguageToolEngine.issues offsets are UTF-16")
    // The emoji is 2 UTF-16 units, so "bad" starts at 3, not 2. LanguageTool counts the same way.
    let emojiText = "a😉bad end"
    let emojiIssues = LanguageToolEngine.issues(
        from: [LTMatch(offset: 3, length: 3, message: "m", shortMessage: "s", replacements: ["good"],
                       ruleId: "R", issueType: "misspelling", categoryId: "TYPOS")],
        text: emojiText)
    check(emojiIssues.count == 1, "issue inside text is kept")
    eq(emojiIssues[0].original, "bad", "UTF-16 offset past an emoji resolves to the right substring")
    let outOfRange = LanguageToolEngine.issues(
        from: [LTMatch(offset: 100, length: 3, message: "", shortMessage: "", replacements: [],
                       ruleId: nil, issueType: nil, categoryId: nil)],
        text: emojiText)
    check(outOfRange.isEmpty, "issue past the end of text is dropped")

    // Chat messages start in lowercase, so the capital-at-sentence-start rule would underline the first
    // word of everything; it is filtered out while every other rule on the same text stays.
    let chatText = "привет как дела"
    let capitalRule = LTMatch(offset: 0, length: 6, message: "m", shortMessage: "", replacements: ["Привет"],
                              ruleId: "UPPERCASE_SENTENCE_START", issueType: "typographical", categoryId: "CASING")
    let otherRule = LTMatch(offset: 7, length: 3, message: "m", shortMessage: "", replacements: ["как,"],
                            ruleId: "COMMA_RULE", issueType: "typographical", categoryId: "PUNCTUATION")
    let filtered = LanguageToolEngine.issues(from: [capitalRule, otherRule], text: chatText)
    check(filtered.count == 1 && filtered[0].ruleId == "COMMA_RULE",
          "the sentence-start capital rule is dropped and other rules are kept")
    check(LanguageToolEngine.issues(from: [capitalRule], text: chatText).isEmpty,
          "a text whose only finding is the capital rule shows no underline")
    check(LanguageToolEngine.issues(
            from: [LTMatch(offset: 0, length: 6, message: "m", shortMessage: "", replacements: [],
                           ruleId: nil, issueType: nil, categoryId: nil)], text: chatText).count == 1,
          "a match with no rule id is not mistaken for an ignored rule")

    print("TextIssue identity")
    let idA = issue(5, 3, original: "teh").id
    let idB = issue(5, 3, original: "teh").id
    eq(idA, idB, "same issue re-checked yields the same id")
    check(idA != issue(6, 3, original: "teh").id, "different location yields a different id")

    print("IssueMerger.merge")
    // LanguageTool fires several rules on one word; the user must be asked about it once.
    let typo = issue(0, 3, kind: .spelling, original: "teh", replacements: ["the"], ruleId: "TYPO")
    let dupe = issue(0, 3, kind: .grammar, original: "teh", replacements: ["the", "tea"], ruleId: "OTHER")
    let sameRange = IssueMerger.merge([typo, dupe])
    check(sameRange.count == 1, "identical ranges collapse to one issue")
    check(sameRange[0].replacements == ["the", "tea"], "replacements are unioned and deduped")

    let overlap = IssueMerger.merge([issue(0, 5, original: "a b c"), issue(2, 3, original: "b c")])
    check(overlap.count == 1 && overlap[0].range.length == 5, "overlapping issue loses to the longer one")

    let disjoint = IssueMerger.merge([issue(10, 2, original: "aa"), issue(0, 2, original: "bb")])
    check(disjoint.count == 2, "disjoint issues both survive")
    check(disjoint[0].range.location == 0, "merge output is sorted by location")
    check(IssueMerger.merge([issue(0, 0, original: "")]).isEmpty, "empty ranges are dropped")

    // Regression: an earlier, shorter match must not automatically beat a later, longer one just
    // because it starts first -- Slack messages with 8+ issues routinely produce this pair shape
    // (a one-word typo rule followed a couple of characters later by a longer grammar rule).
    let earlyShort = issue(0, 2, original: "te", replacements: ["te-fix"])
    let laterLong = issue(1, 5, original: "eh cat", replacements: ["the cat"])
    let lengthWins = IssueMerger.merge([earlyShort, laterLong])
    check(lengthWins.count == 1 && lengthWins[0].range.length == 5,
          "a longer match starting later still wins the cluster")
    check(lengthWins[0].replacements == ["the cat"], "the losing match's own replacements are dropped")

    // Eight separate LanguageTool-style pairs (a short rule plus a longer, later-starting rule on
    // the same word) spread across one long message, each pair cleanly apart from the next -- the
    // shape of the reported Slack bug. Every pair must resolve to exactly its longer match; none of
    // the 8 problem spots may vanish entirely.
    let pairs = (0..<8).flatMap { i -> [TextIssue] in
        let base = i * 20
        return [issue(base, 2, original: "xx"), issue(base + 1, 6, original: "xxxxxx")]
    }
    let mergedPairs = IssueMerger.merge(pairs)
    check(mergedPairs.count == 8, "all 8 distinct problem spots survive, one issue each")
    for i in 0..<(mergedPairs.count - 1) {
        check(NSMaxRange(mergedPairs[i].range) <= mergedPairs[i + 1].range.location,
              "merge output never contains two issues that still overlap each other")
    }

    print("IssueMerger.firstIssue(overlapping:)")
    let picked = [issue(0, 3, original: "teh"), issue(10, 4, original: "wrng")]
    check(IssueMerger.firstIssue(in: picked, overlapping: NSRange(location: 10, length: 4))?.original == "wrng",
          "a selection on an issue finds it")
    check(IssueMerger.firstIssue(in: picked, overlapping: NSRange(location: 11, length: 1))?.original == "wrng",
          "a partial selection inside an issue finds it")
    check(IssueMerger.firstIssue(in: picked, overlapping: NSRange(location: 5, length: 2)) == nil,
          "a selection on clean text finds nothing")
    check(IssueMerger.firstIssue(in: picked, overlapping: NSRange(location: 12, length: 0))?.original == "wrng",
          "a caret inside an issue finds it")

    print("IssueMerger.relocate")
    let teh = issue(4, 3, original: "teh")
    check(IssueMerger.relocate(teh, in: "the teh cat") == NSRange(location: 4, length: 3),
          "unchanged text relocates to the same range")
    // The user typed "Well, " at the start while the panel was open.
    check(IssueMerger.relocate(teh, in: "Well, the teh cat") == NSRange(location: 10, length: 3),
          "text shifted by an edit is found at its new offset")
    check(IssueMerger.relocate(teh, in: "the cat") == nil, "vanished text does not relocate")
    // The old range no longer matches, and two candidates are equally plausible: refuse to guess.
    check(IssueMerger.relocate(teh, in: "xxxx teh teh") == nil, "ambiguous text does not relocate")
    // An exact hit at the original range wins even when the word occurs twice: the text did not move.
    check(IssueMerger.relocate(teh, in: "teh teh cat") == NSRange(location: 4, length: 3),
          "a still-valid range is used without searching")
    check(IssueMerger.relocate(teh, in: "the cat sat on the mat and teh dog", window: 5) == nil,
          "a match far outside the window is not used")
    check(IssueMerger.relocate(issue(0, 0, original: ""), in: "abc") == nil, "empty original never relocates")

    print("TextIssue context capture")
    let ctxIssues = LanguageToolEngine.issues(
        from: [LTMatch(offset: 4, length: 3, message: "m", shortMessage: "s", replacements: ["the"],
                       ruleId: "R", issueType: "misspelling", categoryId: "TYPOS")],
        text: "one teh two")
    eq(ctxIssues[0].contextBefore, "one ", "context before captured (clipped at text start)")
    eq(ctxIssues[0].contextAfter, " two", "context after captured (clipped at text end)")
    let ctxMoved = ctxIssues[0].withRange(NSRange(location: 14, length: 3))
    eq(ctxMoved.contextBefore, "one ", "withRange preserves contextBefore")
    eq(ctxMoved.contextAfter, " two", "withRange preserves contextAfter")
    check(ctxIssues[0].id == TextIssue(range: NSRange(location: 4, length: 3), kind: .spelling,
                                       shortMessage: "s", message: "m", replacements: ["the"],
                                       ruleId: "R", source: .languageTool, original: "teh").id,
          "identity does not depend on context")

    print("IssueMerger.relocate with context")
    // Build an issue the way the engine does, from the text it was checked against.
    func ctxIssue(in text: String, location: Int, length: Int) -> TextIssue {
        LanguageToolEngine.issues(
            from: [LTMatch(offset: location, length: length, message: "", shortMessage: "",
                           replacements: [], ruleId: nil, issueType: nil, categoryId: nil)],
            text: text)[0]
    }
    // Two identical words; a prefix edit shifted everything. Context picks the right occurrence.
    let dogTeh = ctxIssue(in: "teh cat teh dog", location: 8, length: 3)
    check(IssueMerger.relocate(dogTeh, in: "X teh cat teh dog") == NSRange(location: 10, length: 3),
          "context relocates the right one of two identical words after a prefix edit")
    // A different identical occurrence now sits at the old offset; context still finds the true one.
    let aaTail = ctxIssue(in: "start aa end", location: 6, length: 2)
    check(IssueMerger.relocate(aaTail, in: "aa xx start aa end") == NSRange(location: 12, length: 2),
          "context rejects a wrong identical word at a shifted position")
    // The only occurrence in the window has completely different surroundings: refuse.
    check(IssueMerger.relocate(dogTeh, in: "xxxxxxxx teh yyyyy") == nil,
          "a single occurrence with zero context agreement is stale (was wrongly accepted before)")
    // Identical contexts on both candidates: genuinely ambiguous.
    check(IssueMerger.relocate(ctxIssue(in: "ab teh cd", location: 3, length: 3),
                               in: "x ab teh cd ab teh cd") == nil,
          "two candidates with identical contexts stay ambiguous")
    // Unchanged text with context still resolves to the same spot.
    check(IssueMerger.relocate(dogTeh, in: "teh cat teh dog") == NSRange(location: 8, length: 3),
          "unchanged text with context relocates to the same range")

    print("IssueMerger.shift by the applied range")
    // The applier replaced at the RELOCATED range (10), not the stale stored one (4).
    let shiftInput = [issue(2, 2, original: "aa"), issue(20, 3, original: "bbb")]
    let shifted = IssueMerger.shift(shiftInput, replacedRange: NSRange(location: 10, length: 3),
                                    replacementUTF16Length: 5)
    check(shifted[0].range == NSRange(location: 2, length: 2),
          "issue before the applied range is untouched")
    check(shifted[1].range == NSRange(location: 22, length: 3),
          "issue after the applied range slides by the exact delta")
    // An issue the edit reaches into no longer describes any text that exists.
    let overlapped = IssueMerger.shift([issue(10, 6, original: "aabbcc")],
                                       replacedRange: NSRange(location: 12, length: 2),
                                       replacementUTF16Length: 4)
    check(overlapped.isEmpty, "an issue the applied range cuts into is dropped")
    // A shorter replacement slides the rest backwards, not forwards.
    let shrunk = IssueMerger.shift([issue(20, 3, original: "bbb")],
                                   replacedRange: NSRange(location: 10, length: 5),
                                   replacementUTF16Length: 2)
    check(shrunk[0].range == NSRange(location: 17, length: 3), "a shorter replacement slides later issues back")
    // A deletion (empty replacement) is the extreme of the same case.
    let deleted = IssueMerger.shift([issue(20, 3, original: "bbb")],
                                    replacedRange: NSRange(location: 10, length: 4),
                                    replacementUTF16Length: 0)
    check(deleted[0].range == NSRange(location: 16, length: 3), "a deletion slides later issues by its full length")

    print("RecheckPolicy")
    check(RecheckPolicy.shouldRecheck(selectionCheckPending: false),
          "with nothing in flight the post-write pass re-checks")
    check(!RecheckPolicy.shouldRecheck(selectionCheckPending: true),
          "a click's check is left alone: cancelling it is what swallowed the popup")

    print("UnderlineGeometry")
    // Quartz -> AppKit flip. Primary screen 1000 pt tall; a rect whose top is 100 from the top ends up
    // with its bottom at 1000 - 120 = 880 in AppKit coordinates.
    let flipped = UnderlineGeometry.appKitRect(fromQuartz: CGRect(x: 10, y: 100, width: 50, height: 20),
                                               primaryScreenHeight: 1000)
    check(flipped == CGRect(x: 10, y: 880, width: 50, height: 20), "quartz rect flips to AppKit")
    // A window on a taller secondary display can have a negative AppKit y; the formula must not clamp.
    let below = UnderlineGeometry.appKitRect(fromQuartz: CGRect(x: 0, y: 1190, width: 10, height: 20),
                                             primaryScreenHeight: 1000)
    check(below.origin.y == -210, "conversion is unclamped for secondary-display geometry")

    check(UnderlineGeometry.isSingleLine(rangeRect: CGRect(x: 0, y: 0, width: 100, height: 16),
                                         probeRect: CGRect(x: 0, y: 0, width: 8, height: 16)),
          "equal heights are single-line")
    check(!UnderlineGeometry.isSingleLine(rangeRect: CGRect(x: 0, y: 0, width: 100, height: 32),
                                          probeRect: CGRect(x: 0, y: 0, width: 8, height: 16)),
          "a doubled height (wrapped range) is not single-line")
    check(!UnderlineGeometry.isSingleLine(rangeRect: CGRect(x: 0, y: 0, width: 100, height: 16),
                                          probeRect: .zero),
          "a zero probe rect is rejected")

    print("TextSegmenter.paragraphs")
    func tiles(_ ps: [Paragraph], _ text: String) -> Bool {
        var next = 0
        for p in ps {
            if p.range.location != next { return false }
            next = NSMaxRange(p.range)
        }
        return next == (text as NSString).length
    }
    let lfText = "one\ntwo\nthree"
    let lf = TextSegmenter.paragraphs(of: lfText)
    check(lf.count == 3, "LF splits into three paragraphs")
    eq(lf[0].text, "one\n", "separator stays with its paragraph")
    eq(lf[2].text, "three", "last paragraph without a trailing separator")
    check(tiles(lf, lfText), "LF paragraphs tile the text with no gaps")

    let crlfText = "one\r\ntwo"
    let crlf = TextSegmenter.paragraphs(of: crlfText)
    check(crlf.count == 2, "CRLF counts as one separator")
    eq(crlf[0].text, "one\r\n", "CRLF stays with its paragraph")
    check(tiles(crlf, crlfText), "CRLF paragraphs tile the text")

    let blankText = "one\n\nthree"
    let blank = TextSegmenter.paragraphs(of: blankText)
    check(blank.count == 3, "a blank line is its own paragraph")
    check(tiles(blank, blankText), "paragraphs around a blank line tile the text")
    check(TextSegmenter.paragraphs(of: "").isEmpty, "empty text has no paragraphs")
    check(!TextSegmenter.isCheckable(Paragraph(range: NSRange(location: 0, length: 1), text: "\n")),
          "a blank paragraph is not worth checking")

    print("ProofreadCache")
    let cache = ProofreadCache()
    let para = Paragraph(range: NSRange(location: 7, length: 5), text: "hello")
    check(cache.issues(for: para) == nil, "cache starts empty")
    cache.store([issue(1, 2, original: "el")], for: para)
    check(cache.issues(for: para)?.count == 1, "stored issues are found by paragraph text")
    let rebased = ProofreadCache.rebase(cache.issues(for: para)!, to: para.range.location)
    check(rebased[0].range.location == 8, "rebase moves paragraph-local ranges into document coordinates")
    eq(rebased[0].original, "el", "rebase preserves the issue payload")
    cache.prune(keeping: [Paragraph(range: NSRange(location: 0, length: 5), text: "other")])
    check(cache.count == 0, "prune forgets paragraphs no longer in the document")

    print("ProofreadLanguage")
    eq(ProofreadLanguage.resolve(text: "x", setting: "en-US", detected: "ru"), "en-US",
       "an explicit setting overrides detection")
    eq(ProofreadLanguage.resolve(text: "x", setting: "auto", detected: nil), "ru",
       "auto with no detection uses the fallback")
    eq(ProofreadLanguage.resolve(text: "hello there", setting: "auto", detected: "en"), "en",
       "auto uses the detected language")
    eq(ProofreadLanguage.disambiguateCyrillic("привет как дела", candidate: "uk", preferred: "ru"), "ru",
       "Russian text misdetected as Ukrainian falls back to Russian")
    eq(ProofreadLanguage.disambiguateCyrillic("привіт як справи", candidate: "uk", preferred: "ru"), "uk",
       "real Ukrainian keeps its detected language")
    eq(ProofreadLanguage.disambiguateCyrillic("hello", candidate: "en", preferred: "ru"), "en",
       "non-Cyrillic detection is left alone")
    eq(ProofreadLanguage.baseCode("en-US"), "en", "baseCode strips the region")

    print("WordBoundary")
    check(WordBoundary.wordRange(at: 2, in: "hello world") == NSRange(location: 0, length: 5),
          "caret mid-word finds the word")
    check(WordBoundary.wordRange(at: 0, in: "hello world") == NSRange(location: 0, length: 5),
          "caret at word start finds the word")
    check(WordBoundary.wordRange(at: 5, in: "hello world") == NSRange(location: 0, length: 5),
          "caret at word end (right edge click) finds the word just ended")
    check(WordBoundary.wordRange(at: 6, in: "hello  world") == nil,
          "caret in whitespace between words finds nothing")
    check(WordBoundary.wordRange(at: 0, in: "") == nil, "empty text finds nothing")
    check(WordBoundary.wordRange(at: 999, in: "hello") == NSRange(location: 0, length: 5),
          "out-of-bounds caret is clamped to the end")
    check(WordBoundary.wordRange(at: 5, in: "a😉bad end") == NSRange(location: 3, length: 3),
          "UTF-16 offsets stay correct past an emoji")
    check(WordBoundary.wordRange(at: 3, in: "привет мир") == NSRange(location: 0, length: 6),
          "Cyrillic word found")
    check(WordBoundary.wordRange(at: 9, in: "привет мир") == NSRange(location: 7, length: 3),
          "second Cyrillic word found")
    check(WordBoundary.wordRange(at: 3, in: "don't stop") == NSRange(location: 0, length: 5),
          "apostrophe stays inside the word")
    // Foundation segments "cat.dog" as a single word (hostname-style); pin that behaviour.
    check(WordBoundary.wordRange(at: 4, in: "cat.dog") == NSRange(location: 0, length: 7),
          "dotted compound is treated as one word")
    check(WordBoundary.wordRange(at: 3, in: "cat. dog") == NSRange(location: 0, length: 3),
          "caret before a sentence dot picks the preceding word")

    print("ProofreadClickPolicy")
    // The Slack cases, as rules rather than something to retry by hand in a live channel.
    let sentence = "the quick brown fox jumps"
    check(ProofreadClickPolicy.action(selection: NSRange(location: 6, length: 0), caret: 6, in: sentence)
            == .probe(NSRange(location: 4, length: 5)),
          "a plain click inside a word asks about that word")
    check(ProofreadClickPolicy.action(selection: NSRange(location: 3, length: 0), caret: 3, in: sentence)
            == .probe(NSRange(location: 0, length: 3)),
          "a click at a word's right edge picks the word just ended")
    // A double-click selects the word and Slack drops its formatting toolbar right on top of it.
    check(ProofreadClickPolicy.action(selection: NSRange(location: 4, length: 5), caret: 4, in: sentence)
            == .ignore,
          "double-clicking a word leaves the popup alone (the app's own toolbar owns that spot)")
    // Dragging across a paragraph that contains an underlined word: same toolbar, same rule.
    check(ProofreadClickPolicy.action(selection: NSRange(location: 0, length: 25), caret: 0, in: sentence)
            == .ignore,
          "selecting a whole paragraph leaves the popup alone")
    check(ProofreadClickPolicy.action(selection: NSRange(location: 4, length: 1), caret: 4, in: sentence)
            == .ignore,
          "even a one-character selection counts as the user selecting, not asking")
    check(ProofreadClickPolicy.action(selection: NSRange(location: 4, length: 0), caret: 4, in: "the  fox")
            == .dismiss,
          "a click in whitespace closes the popup and keeps the underlines")
    check(ProofreadClickPolicy.action(selection: NSRange(location: 0, length: 0), caret: 0, in: "")
            == .dismiss,
          "a click in an empty field closes the popup")

    print("IssueMerger.capReplacements")
    let capIssue = TextIssue(range: NSRange(location: 0, length: 4), kind: .spelling,
                             shortMessage: "s", message: "m",
                             replacements: ["one", "two", "three", "four", "five"],
                             ruleId: nil, source: .languageTool, original: "orig")
    let capped = IssueMerger.capReplacements([capIssue], limit: 3)
    check(capped[0].replacements == ["one", "two", "three"], "cap 3 keeps the first three in order")
    check(capped[0].id == capIssue.id, "capping preserves identity")
    check(IssueMerger.capReplacements([capIssue], limit: 9)[0].replacements.count == 5,
          "cap larger than the list keeps everything")
    check(IssueMerger.capReplacements([capIssue], limit: 0)[0].replacements == ["one"],
          "limit below 1 is clamped to 1")
    check(IssueMerger.capReplacements([capIssue], limit: 99)[0].replacements.count == 5,
          "limit above 10 is clamped to 10 (list shorter anyway)")

    print("LanguageToolEngine.authParams")
    let loneUser = LanguageToolEngine.authParams(["text": "x"], username: "me@x.com", apiKey: "")
    check(loneUser["username"] == nil && loneUser["apiKey"] == nil, "lone username is dropped (would 400)")
    let loneKey = LanguageToolEngine.authParams(["text": "x"], username: "", apiKey: "abc")
    check(loneKey["apiKey"] == nil, "lone apiKey is dropped")
    let pair = LanguageToolEngine.authParams(["text": "x"], username: "me@x.com", apiKey: "abc")
    check(pair["username"] == "me@x.com" && pair["apiKey"] == "abc", "a full pair is attached")
    check(LanguageToolEngine.authParams(["text": "x"], username: "", apiKey: "")["text"] == "x",
          "original params survive")

    print("HiddenBreaks")
    let glued = "Купить хлеб.Позвонить маме"
    let gluedBreaks = HiddenBreaks(offsets: [12])
    eq(gluedBreaks.checkText(glued), "Купить хлеб.\nПозвонить маме", "a hidden break becomes a newline")
    eq(HiddenBreaks.none.checkText(glued), glued, "no breaks leaves the text alone")
    func ltIssue(_ text: String, _ location: Int, _ length: Int, rule: String = "R") -> TextIssue {
        let ns = text as NSString
        let range = NSRange(location: location, length: length)
        return TextIssue(range: range, kind: .grammar, shortMessage: "", message: "", replacements: ["x"],
                         ruleId: rule, source: .languageTool, original: ns.substring(with: range),
                         contextBefore: "", contextAfter: "\n")
    }
    let checked = gluedBreaks.checkText(glued)
    let mappedBack = gluedBreaks.mapBack([ltIssue(checked, 14, 9)], to: glued)
    check(mappedBack.count == 1 && mappedBack[0].range == NSRange(location: 13, length: 9),
          "an issue after the break moves back by one")
    eq(mappedBack.first?.original ?? "", "озвонить ", "the snapshot is retaken from the field's text")
    let lastWord = gluedBreaks.mapBack([ltIssue(checked, 7, 4)], to: glued)
    eq(lastWord.first?.contextAfter ?? "", ".Позвонить м", "context is the app's text, without our newline")
    check(gluedBreaks.mapBack([ltIssue(checked, 10, 4)], to: glued).isEmpty, "an issue spanning the break is dropped")
    check(HiddenBreaks.none.mapBack([ltIssue(glued, 0, 6)], to: glued) == [ltIssue(glued, 0, 6)],
          "no breaks leaves issues untouched")
    let three = "оди.два.три"
    let threeBreaks = HiddenBreaks(offsets: [8, 4])
    eq(threeBreaks.checkText(three), "оди.\nдва.\nтри", "several breaks, given out of order")
    check(threeBreaks.mapBack([ltIssue(threeBreaks.checkText(three), 10, 3)], to: three).first?.range
          == NSRange(location: 8, length: 3), "the second break shifts by two")
    let found = HiddenBreaks.find(pieces: ["Список:", "купить", " хлеб", "Позвонить"],
                                  in: "Список:купить хлебПозвонить") { _, next in next != 2 }
    check(found.offsets == [7, 18], "a break needs a new line and no whitespace at the seam")
    check(HiddenBreaks.find(pieces: ["жирный", "обычный"], in: "жирныйобычный") { _, _ in false }.isEmpty,
          "inline formatting on one line is not a break")
    // Slack's bulleted list: the markers are text elements of their own but are not in the value.
    let bulletPieces = ["По итогу встречи:", "•", "2 документа - согласовали", "•", "Презентация - согласовали.",
                        "•", "Общую папку (", "https://drive.google.com/x", ") - заполняем", "1.", "Собрать группу"]
    let bulletText = "По итогу встречи:2 документа - согласовалиПрезентация - согласовали.Общую папку (https://drive.google.com/x) - заполняемСобрать группу"
    let itemStarts: Set<Int> = [2, 4, 6, 10]
    let bulletBreaks = HiddenBreaks.find(pieces: bulletPieces, in: bulletText) { _, next in itemStarts.contains(next) }
    let bulletNS = bulletText as NSString
    let expectedItemStarts = ["2 документа", "Презентация", "Общую папку", "Собрать группу"].map { bulletNS.range(of: $0).location }
    check(bulletBreaks.offsets == expectedItemStarts,
          "list markers missing from the value do not stop the item breaks being found (\(bulletBreaks.offsets))")
    eq(bulletBreaks.checkText(bulletText),
       "По итогу встречи:\n2 документа - согласовали\nПрезентация - согласовали.\nОбщую папку (https://drive.google.com/x) - заполняем\nСобрать группу",
       "the meeting notes come out one item per line, link kept inline")
    let aligned = HiddenBreaks.align(pieces: ["один", "ЛИШНЕЕ", "два"], in: "одиндва")
    check(aligned[0] == 0 && aligned[1] == nil && aligned[2] == 4, "a piece that is not in the text is skipped, the rest still align")
    check(HiddenBreaks.find(pieces: ["один", "ЛИШНЕЕ", "два"], in: "одиндва") { _, _ in true }.offsets == [4],
          "pieces either side of a skipped one still meet")

    print("ListMarkers (real Slack text)")
    let slackNumbered = "Итоги встречи:\n1.первый пункт про малако\n2.Второй пункт с точкой.\n3.третий пункт без точки\nПосле списка есть ощибка."
    let slackNS = slackNumbered as NSString
    check(ListMarkers.markerEnds(in: slackNumbered) == ["1.первый", "2.Второй", "3.третий"].map { slackNS.range(of: $0).location + 2 },
          "a number glued to its item gets a space after the marker")
    let slackBulleted = "Список дел:\n\u{E506}купить хлеп\n\u{E506}Позвонить маме."
    check(ListMarkers.markerEnds(in: slackBulleted).count == 2, "Slack's private-use bullet counts as a marker")
    check(ListMarkers.markerEnds(in: "•Пункт\n12)Текст\na.Буква").count == 3, "typed bullets, 12) and a. are markers")
    check(ListMarkers.markerEnds(in: "1.5 кг муки\n-5 градусов\n1. Уже с пробелом\nвнутри 1.строки").isEmpty,
          "decimals, negative numbers, separated markers and mid-line numbers are left alone")
    let spaced = HiddenBreaks.none.addingSpaces(ListMarkers.markerEnds(in: slackNumbered))
    eq(spaced.checkText(slackNumbered),
       "Итоги встречи:\n1. первый пункт про малако\n2. Второй пункт с точкой.\n3. третий пункт без точки\nПосле списка есть ощибка.",
       "the check sees '1. первый', not '1.первый'")
    let spacedCheck = spaced.checkText(slackNumbered) as NSString
    let typoInCheck = spacedCheck.range(of: "ощибка")
    let typoBack = spaced.mapBack([ltIssue(spacedCheck as String, typoInCheck.location, typoInCheck.length)], to: slackNumbered)
    check(typoBack.first?.range == slackNS.range(of: "ощибка"), "an issue after the markers maps back onto the field's text")

    print("AppOffsetMap (real Slack text)")
    // Slack's own string drops the newlines between list items, but keeps the one after a quote.
    let slackApp = "Итоги встречи:1.первый пункт про малако2.Второй пункт с точкой.3.третий пункт без точкиПосле списка есть ощибка."
    let offsetMap = AppOffsetMap(value: slackNumbered, app: slackApp)
    check(offsetMap != nil && offsetMap?.isIdentity == false, "the value lines up with Slack's string")
    let typoValue = slackNS.range(of: "ощибка")
    check(offsetMap?.appRange(typoValue) == (slackApp as NSString).range(of: "ощибка"),
          "a word after four dropped newlines lands on the same word in Slack's offsets")
    check(offsetMap?.appRange(slackNS.range(of: "малако")) == (slackApp as NSString).range(of: "малако"),
          "a word after one dropped newline lands on the same word")
    check(offsetMap?.valueOffset((slackApp as NSString).range(of: "Второй").location) == slackNS.range(of: "Второй").location,
          "a caret in Slack's offsets comes back to the value's")
    let quoteValue = "Это цитата с ашибкой\nТекст после цитаты."
    check(AppOffsetMap(value: quoteValue, app: quoteValue)?.isIdentity == true, "identical texts need no translation")
    let emojiValue = "Отлично \n\n сделали, спосибо"
    check(AppOffsetMap(value: emojiValue, app: "Отлично  сделали, спосибо")?.appRange((emojiValue as NSString).range(of: "спосибо"))
          == ("Отлично  сделали, спосибо" as NSString).range(of: "спосибо"), "an emoji's two newlines are dropped too")
    check(AppOffsetMap(value: "abc", app: "abd") == nil, "texts that differ in more than newlines are not lined up")

    print("Seam candidates")
    func seamIssue(_ text: String, _ word: String, fix: String) -> TextIssue {
        let range = (text as NSString).range(of: word)
        return TextIssue(range: range, kind: .punctuation, shortMessage: "", message: "", replacements: [fix],
                         ruleId: "R", source: .languageTool, original: word)
    }
    let seamSentence = "согласовали.Презентация"
    check(HiddenBreaks.seamCandidates(of: seamIssue(seamSentence, "Презентация", fix: " Презентация"), in: seamSentence)
          == [(seamSentence as NSString).range(of: "Презентация").location], "a fix that inserts a space marks the issue start")
    let gluedWord = "купить хлебПозвонить маме"
    check(HiddenBreaks.seamCandidates(of: seamIssue(gluedWord, "хлебПозвонить", fix: "хлеб Позвонить"), in: gluedWord)
          == [(gluedWord as NSString).range(of: "Позвонить").location], "lowercase running into a capital is a candidate")
    let acronym = "Пилот на VRS и ИИ"
    check(HiddenBreaks.seamCandidates(of: seamIssue(acronym, "VRS", fix: "VR"), in: acronym).isEmpty
          && HiddenBreaks.seamCandidates(of: seamIssue(acronym, "ИИ", fix: "ИИ."), in: acronym).isEmpty,
          "capitals inside an acronym are not candidates")

    print("ProofreadSkips")
    func skipIssue(_ location: Int, before: String, after: String) -> TextIssue {
        TextIssue(range: NSRange(location: location, length: 5), kind: .spelling, shortMessage: "", message: "",
                  replacements: ["слово"], ruleId: "MORFOLOGIK", source: .languageTool, original: "слвоо",
                  contextBefore: before, contextAfter: after)
    }
    var skips = ProofreadSkips()
    skips.insert(skipIssue(10, before: "это моё ", after: " тут"))
    check(skips.filter([skipIssue(25, before: "это моё ", after: " тут")]).isEmpty,
          "a skipped place stays skipped after the text before it moved")
    check(skips.filter([skipIssue(40, before: "другое ", after: " там")]).count == 1,
          "the same word elsewhere is still reported")


    print("ProofreadKeyPolicy")
    func pk(_ key: Int, browsing: Bool = false, atFirst: Bool = true, layout: PopupLayout = .column,
            cmd: Bool = false, opt: Bool = false, shift: Bool = false) -> ProofreadKeyPolicy.Action {
        ProofreadKeyPolicy.action(keyCode: key, command: cmd, control: false, option: opt, shift: shift,
                                  browsing: browsing, atFirst: atFirst, layout: layout)
    }
    check(pk(123) == .passAndClose(reason: "navigation") && pk(124) == .passAndClose(reason: "navigation")
          && pk(126) == .passAndClose(reason: "navigation"), "Left/Right/Up move the caret and close the fixes")
    check(pk(125) == .enter, "Down goes into the fixes")
    check(pk(48) == .nextIssue && pk(48, shift: true) == .previousIssue, "Tab and Shift+Tab walk the issues")
    check(pk(36) == .apply, "Return applies the first fix")
    check(pk(36, cmd: true) == .fixAll && pk(36, browsing: true) == .apply, "Cmd+Return is Fix all, plain Return one fix")
    check(pk(36, cmd: true, shift: true) == .passAndClose(reason: "modifier"), "Cmd+Shift+Return is not Fix all")
    check(pk(53) == .close(reason: "esc"), "Esc closes")
    check(pk(49, cmd: true) == .passAndClose(reason: "modifier"), "a shortcut closes and goes through")
    check(pk(125, browsing: true) == .move(dx: 0, dy: 1) && pk(126, browsing: true, atFirst: true) == .leave,
          "inside: Down moves, Up from the first backs out")
    check(pk(53, browsing: true) == .leave, "inside: Esc backs out")
    check(pk(36, browsing: true) == .apply, "inside: Return applies the selected fix")

    print("FixAll")
    do {
        let text = "Тут малако и ощибка."
        let milk = issue(4, 6, original: "малако", replacements: ["молоко", "малака"])
        let typo = issue(13, 6, original: "ощибка", replacements: ["ошибка"])
        let none = issue(0, 3, original: "Тут", replacements: [])
        let all = FixAll.apply([milk, typo, none], to: text)
        eq(all.text, "Тут молоко и ошибка.", "every issue gets its first fix")
        check(all.fixed == 2, "an issue without a fix is left and not counted")
        check(FixAll.fixable([milk, none]).count == 1, "only issues with a fix are fixable")
        let moved = FixAll.apply([milk, typo], to: "Ну, тут малако и ощибка.")
        eq(moved.text, "Ну, тут молоко и ошибка.", "issues are relocated when the text moved")
        let clash = FixAll.apply([issue(4, 6, original: "малако", replacements: ["молоко"]),
                                  issue(4, 8, original: "малако и", replacements: ["X"])], to: text)
        check(clash.fixed == 1, "overlapping issues are fixed once")
        check(FixAll.apply([typo], to: "совсем другой текст").fixed == 0, "a vanished issue is skipped")
    }

    print("PersonalDictionary")
    do {
        let words = PersonalDictionary.set(["Ёжик", " BindAll "])
        check(words == ["ежик", "bindall"], "words are trimmed, lowercased and ё folds into е")
        let spelled = issue(0, 5, kind: .spelling, original: "ежик")
        let grammar = issue(6, 7, kind: .grammar, original: "bindall")
        let other = issue(14, 4, kind: .spelling, original: "тест")
        let kept = PersonalDictionary.filter([spelled, grammar, other], words: words)
        check(kept.map(\.original) == ["bindall", "тест"], "only spelling issues on dictionary words are dropped")
        eqArr(PersonalDictionary.adding("ЁЖИК", to: ["Ёжик"]), ["Ёжик"], "a word already there is not added twice")
        eqArr(PersonalDictionary.adding("Swearl,", to: ["Ёжик"]), ["Ёжик", "Swearl"], "punctuation is stripped on add")
        eqArr(PersonalDictionary.adding("  ", to: []), [], "a blank word is ignored")
    }

    print("PreSendPolicy")
    do {
        func ps(_ key: Int, cmd: Bool = false, shift: Bool = false, armed: Bool = true, warning: Bool = false,
                pid: pid_t = 7) -> PreSendPolicy.Action {
            PreSendPolicy.action(keyCode: key, command: cmd, shift: shift, option: false, control: false,
                                 state: PreSendPolicy.State(armed: armed, warning: warning, pid: 7), targetPid: pid)
        }
        check(ps(36) == .warn, "Return with issues left is held back once")
        check(ps(36, armed: false) == .pass, "Return with no issues goes through")
        check(ps(36, shift: true) == .pass && ps(36, cmd: true) == .pass, "Shift+Return and Cmd+Return are not held")
        check(ps(0) == .pass, "typing goes through")
        check(ps(36, pid: 9) == .pass, "a key for another app is never touched")
        check(ps(36, warning: true) == .send, "Return again sends")
        check(ps(48, warning: true) == .review, "Tab shows the issues")
        check(ps(36, cmd: true, warning: true) == .fixAll, "Cmd+Return fixes all")
        check(ps(53, warning: true) == .dismiss, "Esc goes back to the text")
        check(ps(0, warning: true) == .passAndDismiss, "typing on goes through and drops the warning")
        eq(PreSendPolicy.warningText(count: 1).prefix(12).description, "1 issue left", "singular wording")
    }

    print("TextOccurrence.nearest")
    do {
        let text = "малако и снова малако, опять малако" as NSString
        check(TextOccurrence.nearest("снова", in: text, to: 0)?.location == 9, "a single occurrence")
        check(TextOccurrence.nearest("малако", in: text, to: 14)?.location == 15, "the nearest of three")
        check(TextOccurrence.nearest("малако", in: text, to: 100)?.location == 29, "the last when the estimate is past it")
        check(TextOccurrence.nearest("молоко", in: text, to: 5) == nil, "none when absent")
        check(TextOccurrence.nearest("x", in: "" as NSString, to: 0) == nil && TextOccurrence.nearest("", in: text, to: 0) == nil,
              "nothing in an empty text or for an empty word")
    }
}
