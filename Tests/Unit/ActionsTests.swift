import AVFoundation
import CoreGraphics
import Foundation

func runActionsTests() {
    print("HistoryEntry applied")
    do {
        let old = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":0,"kind":"action","input":"a","output":"b","engine":"x"}]"#
        let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: Data(old.utf8))
        check(decoded?.first?.applied == true, "an entry from before the flag counts as applied")
        var shown = HistoryEntry(date: Date(), kind: .translate, input: "a", output: "b", engine: "x")
        shown.applied = false
        let back = (try? JSONEncoder().encode([shown])).flatMap { try? JSONDecoder().decode([HistoryEntry].self, from: $0) }
        check(back?.first?.applied == false, "a shown-only entry stays shown-only")
    }

    print("MaskAISlop keeps what the user typed")
    check(MaskAISlop.apply(to: "«Да» — сказал он", keeping: "«да» — сказал он") == "«Да» — сказал он", "their quotes and dash stay")
    check(MaskAISlop.apply(to: "«Да» — сказал он", keeping: "да, сказал он") == "\"Да\" - сказал он", "the model's own are cleaned")
    check(MaskAISlop.apply(to: "ok 🚀 go", keeping: "ok 🚀 go") == "ok 🚀 go", "their emoji stays")

    print("KeyboardLayoutMap and local transforms")
    check(KeyboardLayoutMap.convert("Ghbdtn? rfr ltkf") == "Привет, как дела", "US keys meant as Russian")
    check(KeyboardLayoutMap.convert("руддщ цщкдв") == "hello world", "Russian keys meant as US")
    check(KeyboardLayoutMap.convert("Ghbdtn 2026") == "Привет 2026", "digits and spaces stay")
    check(TextTool.uppercase.apply(to: "Привет") == "ПРИВЕТ" && TextTool.lowercase.apply(to: "ПрИвЕт") == "привет", "case tools")
    check(TextTool.keyboardLayout.apply(to: "Ghbdtn") == "Привет", "the layout tool")
    check(!ActionKey.defaults.contains { key in TextTool.allCases.contains { $0.title == key.label } }, "the tools are no action keys")

    print("TextToolMigration")
    do {
        let hotkey = HotkeyConfig(keyCode: 32, modifiers: HotkeyModifiers(command: true, option: true), repeatCount: 1)
        var upper = ActionKey(label: "Капс", prompt: TextTool.uppercase.legacyPrompt)
        upper.hotkey = hotkey
        let edited = ActionKey(label: "lowercase", prompt: "Make it lowercase, keep names capitalized.")
        let polite = ActionKey(label: "Polite", prompt: "Be polite.")
        let (keys, hotkeys) = TextToolMigration.migrate([upper, edited, polite], hotkeys: [:])
        check(keys.map(\.label) == ["lowercase", "Polite"], "an untouched built-in key becomes the tool; an edited one stays")
        check(hotkeys == ["uppercase": hotkey], "its shortcut moves to the tool")
        check(TextToolMigration.migrate(keys, hotkeys: hotkeys) == (keys, hotkeys), "a second pass changes nothing")
    }

    print("TextDiff changedShare")
    check(TextDiff.changedShare(TextDiff.words(old: "один два три четыре", new: "один два три пять")) < 0.5, "one word of four: the diff")
    check(TextDiff.changedShare(TextDiff.words(old: "Привет, как дела", new: "Hi, how are you")) > 0.5, "a translation: the result")
    check(TextDiff.changedShare(TextDiff.words(old: "", new: "inserted")) == 1, "an insertion: the result")
    check(TextDiff.changedShare([]) == 0, "nothing: no change")

    print("EdgeWhitespace")
    check(EdgeWhitespace.wrap("Fixed line", like: "fixd line\n") == "Fixed line\n", "a line keeps its line break")
    check(EdgeWhitespace.wrap(" Word ", like: " word") == " Word", "the original's edges, not the result's")
    check(EdgeWhitespace.wrap("Text", like: "text") == "Text", "no edges, nothing added")
    check(EdgeWhitespace.wrap("", like: "text\n") == "", "an empty result stays empty")
    check(EdgeWhitespace.wrap("A", like: "  \n") == "A", "an all-blank original adds nothing")

    print("ReplaceTarget")
    check(ReplaceTarget.wholeField(original: "Строка один\nСтрока два", now: "Строка один\n\nСтрока два\n") == NSRange(location: 0, length: 24),
          "the whole field, re-read with other line breaks: all of it as it reads now")
    check(ReplaceTarget.wholeField(original: "Строка один", now: "Строка один и ещё") == nil, "text typed since: not overwritten")
    let draft = "one two three two"
    let two = NSRange(location: 14, length: 3)
    check(ReplaceTarget.range(two, in: draft, now: draft) == two, "unchanged text: the same range")
    check(ReplaceTarget.range(two, in: draft, now: draft + " and more") == two,
          "typed after it: the occurrence where it was, not the first one")
    let three = NSRange(location: 8, length: 5)
    check(ReplaceTarget.range(three, in: draft, now: "zero " + draft) == NSRange(location: 13, length: 5),
          "typed before it: found again further on")
    check(ReplaceTarget.range(two, in: draft, now: "one three") == nil, "gone: nowhere to put it")
    check(ReplaceTarget.range(NSRange(location: 0, length: 17), in: draft, now: draft + "!") == nil,
          "the whole field changed: not guessed")

    print("ActionKey")
    check(ActionKey.defaults.allSatisfy { !$0.label.isEmpty }, "built-in keys are named")
    eq(ActionKey(label: "", prompt: "Line one\nline two").title, "Line one line two", "an unnamed key is titled by its prompt")
    let legacy = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","key":"w","label":"Layout","prompt":"P"}"#
    check((try? JSONDecoder().decode(ActionKey.self, from: Data(legacy.utf8)))?.label == "Layout", "a key saved with the retired suffix still decodes")

    print("History ring buffer")
    func entry(_ output: String) -> HistoryEntry {
        HistoryEntry(date: Date(), kind: .action, input: "in", output: output, engine: "test")
    }
    var hist: [HistoryEntry] = []
    for i in 1...5 { hist = HistoryEntry.appending(entry("e\(i)"), to: hist, limit: 3) }
    check(hist.count == 3, "ring buffer trims to limit")
    eq(hist.first?.output ?? "nil", "e5", "newest entry first")
    eq(hist.last?.output ?? "nil", "e3", "oldest kept entry is e3")
    let single = HistoryEntry.appending(entry("only"), to: [], limit: 3)
    check(single.count == 1 && single.first?.output == "only", "append to empty list")

    print("MaskAISlop")
    eq(MaskAISlop.apply(to: "a — b"), "a - b", "em dash → hyphen")
    eq(MaskAISlop.apply(to: "a – b"), "a - b", "en dash → hyphen")
    eq(MaskAISlop.apply(to: "\u{201C}hi\u{201D}"), "\"hi\"", "smart double quotes → straight")
    eq(MaskAISlop.apply(to: "it\u{2019}s"), "it's", "fancy apostrophe → straight")
    eq(MaskAISlop.apply(to: "hi 😀 there"), "hi there", "emoji removed (adjacent doubled space swallowed)")
    eq(MaskAISlop.apply(to: "wait\u{2026}"), "wait...", "ellipsis → three dots")
    eq(MaskAISlop.apply(to: "a\u{00A0}b"), "a b", "nbsp → space")
    eq(MaskAISlop.apply(to: "plain text"), "plain text", "plain text unchanged")

    print("MaskAISlop formatting preservation")
    // The normalizer must never change the layout of the text: line breaks, paragraphs,
    // indentation and alignment have to come out exactly as they went in.
    func preserved(_ text: String, _ message: String) {
        eq(MaskAISlop.apply(to: text), text, message)
    }
    preserved("line one\nline two", "newlines preserved")
    preserved("para one\n\npara two", "blank line between paragraphs preserved")
    preserved("a\tb\tc", "tabs preserved")
    preserved("win\r\nline", "CRLF preserved")
    preserved("\nstart", "leading newline preserved")
    preserved("end\n", "trailing newline preserved")
    preserved("    indented code", "leading-space indentation preserved")
    preserved("col1  col2   col3", "inner space runs (alignment) preserved")
    preserved("- item 1\n- item 2\n  - nested", "markdown list structure preserved")
    preserved("# Header\n\nBody text.", "markdown header + paragraph preserved")
    preserved("```\nlet x = 1\n    let y = 2\n```", "fenced code block with indentation preserved")
    preserved("Привет, мир!\nКак дела?", "cyrillic multi-line text untouched")
    preserved("cafe\u{0301}".precomposedStringWithCanonicalMapping, "precomposed accents (NFC) untouched")

    // Replacements keep the surrounding layout intact.
    eq(MaskAISlop.apply(to: "  a — b\n\tc \u{201C}d\u{201D}"), "  a - b\n\tc \"d\"",
       "replacements do not disturb indentation/newlines/tabs")
    eq(MaskAISlop.apply(to: "x 😀  y"), "x  y", "emoji strip swallows only one adjacent space")
    eq(MaskAISlop.apply(to: "😀line\nkeep  it"), "line\nkeep  it", "strip at start does not touch later spacing")

    print("TextDiff")
    let diffParts = TextDiff.words(old: "Привет как дела малако", new: "Привет, как дела молоко")
    check(diffParts == [.removed("Привет "), .added("Привет, "), .same("как дела "), .removed("малако"), .added("молоко")],
          "changed words are removed and added, the rest kept (\(diffParts))")
    func joined(_ parts: [TextDiff.Part], keepAdded: Bool) -> String {
        parts.map { part -> String in
            switch part {
            case .same(let s): s
            case .added(let s): keepAdded ? s : ""
            case .removed(let s): keepAdded ? "" : s
            }
        }.joined()
    }
    let longOld = "Это первый абзац.\n\nВторой абзац, с ошибкой малако.", longNew = "Это первый абзац.\n\nВторой абзац с молоком."
    let longParts = TextDiff.words(old: longOld, new: longNew)
    check(joined(longParts, keepAdded: true) == longNew && joined(longParts, keepAdded: false) == longOld,
          "the parts rebuild both texts exactly, newlines included")
    check(!TextDiff.hasChanges(TextDiff.words(old: "same text", new: "same text")), "identical texts have no changes")
    check(TextDiff.tokens("  a b") == ["  ", "a ", "b"], "leading whitespace is its own token")

    print("MaskAISlop rules")
    eq(MaskAISlop.apply(to: "a — b", rules: []), "a — b", "with no rules nothing changes")
    eq(MaskAISlop.apply(to: "a — b “x”", rules: [.dashes]), "a - b “x”", "only the chosen rule runs")
    eq(MaskAISlop.apply(to: "Use `a — b` or see https://x.com/a—b — ok", rules: [.dashes]),
       "Use `a — b` or see https://x.com/a—b - ok", "inline code and URLs are left alone")
    eq(MaskAISlop.apply(to: "```\nlet s = “x”\n```\n“y”", rules: [.quotes]), "```\nlet s = “x”\n```\n\"y\"",
       "fenced code is left alone")
    eq(MaskAISlop.apply(to: "### Plan\nThis is **important** and __clear__.", rules: [.markdown]),
       "Plan\nThis is important and clear.", "markdown leftovers are removed")
    eq(MaskAISlop.apply(to: "Shipped it! 🎉\nGo 🚀 now", rules: [.decorativeEmoji]), "Shipped it!\nGo 🚀 now",
       "only emoji at the end of a line go")
    eq(MaskAISlop.apply(to: "Here is the plan.\n\nLet me know if you have any questions!", rules: [.closers]),
       "Here is the plan.", "a sign-off line is dropped")
    eq(MaskAISlop.apply(to: "План готов.\nЕсли остались вопросы — пишите!", rules: [.closers]), "План готов.",
       "Russian sign-offs too")
    eq(MaskAISlop.apply(to: "10\u{00A0}km", rules: [.spaces]), "10 km", "non-breaking spaces become spaces")
    eq(MaskAISlop.apply(to: "10\u{00A0}km", rules: []), "10\u{00A0}km", "and stay without the rule")
    check(MaskAISlop.stockPhrases(in: "We're thrilled to delve into this game-changer. Важно отметить, что") == ["delve", "game-changer", "важно отметить"],
          "stock phrases are found in both languages")

    print("UsageLog")
    let usageDir = FileManager.default.temporaryDirectory.appendingPathComponent("bindly-usage-\(UUID().uuidString)")
    let usageLog = UsageLog(directory: usageDir)
    let usageSemaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var usageRead: [UsageEvent] = []
    nonisolated(unsafe) var usageFile = ""
    let usageEvent = UsageEvent(time: Date(timeIntervalSince1970: 1_780_000_000), feature: .autocomplete, kind: .dismissed,
                                app: "com.tinyspeck.slackmacgap", ms: nil, reason: "esc", detail: nil)
    Task {
        await usageLog.append(usageEvent)
        await usageLog.append(UsageEvent(time: .now, feature: .fix, kind: .applied, app: nil, ms: 420, reason: nil, detail: "source:hotkey"))
        usageRead = await usageLog.events()
        usageFile = await usageLog.fileURL(for: usageEvent.time).lastPathComponent
        await usageLog.clear()
        usageSemaphore.signal()
    }
    usageSemaphore.wait()
    check(usageRead.count == 2 && usageRead.first == usageEvent, "events are appended and read back in order")
    check(usageFile.hasPrefix("usage-") && usageFile.hasSuffix(".jsonl") && usageFile.count == "usage-2026-05.jsonl".count,
          "one file per month (\(usageFile))")
    let usageEncoder = JSONEncoder(); usageEncoder.dateEncodingStrategy = .iso8601
    let usageKeys = Set(((try? JSONSerialization.jsonObject(with: usageEncoder.encode(usageEvent))) as? [String: Any] ?? [:]).keys)
    check(usageKeys.isSubset(of: ["time", "feature", "kind", "app", "ms", "reason", "detail"]),
          "an event has only metadata fields, no room for typed text")
    check(!FileManager.default.fileExists(atPath: usageDir.path), "clear removes the data")

    print("HistoryMenuTitle")
    do {
        func entry(_ output: String) -> HistoryEntry {
            HistoryEntry(date: Date(), kind: .action, input: "in", output: output, engine: "Apple")
        }
        eq(HistoryMenuTitle.title(for: entry("Short one")), "Short one", "a short result is shown as is")
        eq(HistoryMenuTitle.title(for: entry("Line one\nline two")), "Line one line two", "lines are joined into one")
        let long = HistoryMenuTitle.title(for: entry(String(repeating: "слово ", count: 20)))
        check(long.count <= HistoryMenuTitle.maxLength && long.hasSuffix("…"), "a long result is cut with an ellipsis")
    }

    print("ActionKey showOnly")
    do {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","key":"w","label":"L","prompt":"P"}"#
        let decoded = try? JSONDecoder().decode(ActionKey.self, from: Data(old.utf8))
        check(decoded?.showOnly == false && decoded?.label == "L", "a key saved before showOnly decodes as replacing")
        var shown = ActionKey(label: "Explain", prompt: "Explain")
        shown.showOnly = true
        let round = (try? JSONEncoder().encode(shown)).flatMap { try? JSONDecoder().decode(ActionKey.self, from: $0) }
        check(round?.showOnly == true, "showOnly survives a round trip")
    }
}
