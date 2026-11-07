import AppKit
import ApplicationServices
import Carbon.HIToolbox

setvbuf(stdout, nil, _IONBF, 0)
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".build/e2e")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// MARK: - Report

struct Row { let group: String; let name: String; let status: String; let note: String }
nonisolated(unsafe) var rows: [Row] = []
nonisolated(unsafe) var group = ""

func record(_ name: String, _ ok: Bool, _ note: String = "") {
    rows.append(Row(group: group, name: name, status: ok ? "OK" : "FAIL", note: note))
    print("\(ok ? "  OK  " : "  FAIL") \(group) / \(name)\(note.isEmpty ? "" : " — \(note)")")
}
func skip(_ name: String, _ why: String) {
    rows.append(Row(group: group, name: name, status: "SKIP", note: why))
    print("  SKIP \(group) / \(name) — \(why)")
}

// MARK: - TextEdit field

let docURL = outDir.appending(path: "e2e-doc-\(Int(Date().timeIntervalSince1970)).txt")
var textEditPid: pid_t = 0

func textEditField() -> AXUIElement? {
    guard let el = E2E.focusedElement(of: textEditPid),
          (E2E.attr(el, kAXRoleAttribute) as? String) == "AXTextArea" else { return nil }
    return el
}
func fieldText() -> String { textEditField().map(E2E.value) ?? "" }

/// Brings the TextEdit document forward the way a person would, with a click into its text: from a
/// background process `activate()` is not always honoured.
func focusTextEdit() {
    NSRunningApplication(processIdentifier: textEditPid)?.activate()
    E2E.pause(0.3)
    if textEditField() != nil, NSWorkspace.shared.frontmostApplication?.processIdentifier == textEditPid { return }
    let app = AXUIElementCreateApplication(textEditPid)
    if let window = (E2E.attr(app, kAXWindowsAttribute) as? [AXUIElement])?.first,
       let area = E2E.find(in: window, depth: 6, { (E2E.attr($0, kAXRoleAttribute) as? String) == "AXTextArea" }),
       let frame = E2E.frame(area) {
        E2E.click(CGPoint(x: frame.midX, y: frame.maxY - 30))
        E2E.pause(0.4)
    }
}

/// Empties the document and leaves the caret in it.
func clearField() {
    focusTextEdit()
    E2E.key(kVK_ANSI_A, .maskCommand)
    E2E.key(kVK_Delete)
    E2E.pause(0.4)
    _ = E2E.wait(2) { fieldText().isEmpty }
}

func openTextEdit() -> Bool {
    try? "".write(to: docURL, atomically: true, encoding: .utf8)
    func openDoc() {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", "TextEdit", docURL.path]
        try? open.run(); open.waitUntilExit()
    }
    openDoc()
    guard E2E.wait(8, { NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first != nil }) else { return false }
    textEditPid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first!.processIdentifier
    for _ in 0..<2 {
        if E2E.wait(8, { focusTextEdit(); return textEditField() != nil }) {
            moveTextEditToMainScreen()
            return true
        }
        openDoc()
    }
    return false
}

/// Keeps every run on the primary display: menus and panels behave differently on a second one.
func moveTextEditToMainScreen() {
    let app = AXUIElementCreateApplication(textEditPid)
    guard let window = (E2E.attr(app, kAXWindowsAttribute) as? [AXUIElement])?.first else { return }
    var origin = CGPoint(x: 120, y: 100)
    var size = CGSize(width: 720, height: 420)
    for _ in 0..<3 {
        if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v) }
        if let p = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p) }
        E2E.pause(0.4)
        if let frame = E2E.frame(window), abs(frame.minX - origin.x) < 2 { break }
    }
    print("    TextEdit window at \(E2E.frame(window) ?? .zero)")
    focusTextEdit()
}

/// Quartz rect of the first occurrence of `word` in the TextEdit field.
func wordRect(_ word: String) -> CGRect? {
    guard let el = textEditField() else { return nil }
    let range = (E2E.value(el) as NSString).range(of: word)
    guard range.location != NSNotFound else { return nil }
    return E2E.bounds(range, in: el)
}

func suggestionsVisible() -> Bool { E2E.window("BindAll Suggestions") != nil || E2E.window("BindAll Inline") != nil }

func switchInputSourceAndBack() -> Bool {
    guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let list = TISCreateInputSourceList([kTISPropertyInputSourceIsSelectCapable: true,
                                              kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource!] as CFDictionary,
                                             false)?.takeRetainedValue() as? [TISInputSource],
          let other = list.first(where: { !CFEqual($0, current) }) else { return false }
    TISSelectInputSource(other)
    E2E.pause(0.5)
    TISSelectInputSource(current)
    return true
}

// MARK: - Scenarios

func autocompleteScenarios() {
    group = "Autocomplete"
    clearField()
    var since = Date()
    E2E.type("Сегодня мы обсуждали прив")
    let shown = E2E.wait(3) { suggestionsVisible() }
    record("a suggestion appears while typing", shown,
           shown ? "" : "no suggestion window; events: \(E2E.events(since: since).map { "\($0.feature).\($0.kind)" })")
    record("at the end of a line it is inline gray text", E2E.window("BindAll Inline") != nil,
           E2E.window("BindAll Inline") == nil ? "shown as \(E2E.windows().map(\.name))" : "")
    let before = fieldText()
    E2E.key(kVK_Tab)
    let accepted = E2E.wait(2) { fieldText().count > before.count }
    record("Tab accepts it", accepted, accepted ? "→ \(fieldText().split(separator: " ").last ?? "")" : "text stayed \"\(before)\"")

    E2E.type(" прив")
    _ = E2E.wait(3) { suggestionsVisible() }
    let typed = fieldText()
    since = Date()
    E2E.key(kVK_LeftArrow)
    let closed = E2E.wait(1.5) { !suggestionsVisible() }
    record("← moves the caret and closes the suggestion", closed && fieldText() == typed,
           closed ? "" : "still visible")
    record("…and is logged as a navigation dismissal", E2E.hasEvent("autocomplete", "dismissed", since: since, reason: "navigation"))
    E2E.key(kVK_RightArrow)

    E2E.type("е")
    _ = E2E.wait(3) { suggestionsVisible() }
    E2E.key(kVK_DownArrow)
    let listOpened = E2E.wait(1.5) { E2E.window("BindAll Suggestions") != nil && E2E.window("BindAll Inline") == nil }
    record("↓ opens the list from inline text", listOpened, listOpened ? "" : "windows: \(E2E.windows().map(\.name))")
    E2E.key(kVK_Escape)
    E2E.pause(0.3)
    record("Esc backs out of the list (it stays up)", suggestionsVisible())
    E2E.key(kVK_Escape)
    record("Esc again closes it", E2E.wait(1) { !suggestionsVisible() })

    E2E.type(" и прив")
    _ = E2E.wait(3) { suggestionsVisible() }
    since = Date()
    if switchInputSourceAndBack() {
        record("switching the input language closes it", E2E.wait(1.5) { !suggestionsVisible() }
               && E2E.hasEvent("autocomplete", "dismissed", since: since, reason: "languageSwitch"))
    } else {
        skip("switching the input language closes it", "only one keyboard input source is enabled")
    }

    // Mid-line: the list, not inline text.
    E2E.type(" конец")
    for _ in 0..<5 { E2E.key(kVK_LeftArrow) }
    E2E.type("прив")
    let midLine = E2E.wait(3) { E2E.window("BindAll Suggestions") != nil }
    record("in the middle of a line the list is shown", midLine && E2E.window("BindAll Inline") == nil,
           midLine ? "" : "windows: \(E2E.windows().map(\.name))")
    E2E.key(kVK_Escape)
}

func proofreadScenarios() {
    group = "Proofread"
    clearField()
    E2E.type("Тут есть малако, ощибка и граматика в тексте. ")
    let underlined = E2E.wait(12) { E2E.underlineCount() >= 3 }
    record("three typos are underlined", underlined, "count \(E2E.underlineCount())")
    snapshotField("proofread-underlines")

    guard let milk = wordRect("малако") else { record("word geometry", false, "TextEdit gave no rect"); return }
    E2E.click(CGPoint(x: milk.midX, y: milk.midY))
    var popup = E2E.wait(4) { E2E.window("BindAll Fixes") != nil }
    record("clicking an underlined word opens the fixes", popup)
    if let fixes = E2E.window("BindAll Fixes") { E2E.snapshot(fixes.bounds, to: outDir.appending(path: "fixes.png")) }
    if popup {
        let text = fieldText()
        E2E.key(kVK_LeftArrow)
        record("← moves the caret and closes the fixes", E2E.wait(1.5) { E2E.window("BindAll Fixes") == nil } && fieldText() == text)
        E2E.click(CGPoint(x: milk.midX, y: milk.midY))
        popup = E2E.wait(4) { E2E.window("BindAll Fixes") != nil }
        E2E.allowBareReturn = true
        E2E.key(kVK_Return)
        E2E.allowBareReturn = false
        record("Return applies the first fix", E2E.wait(4) { !fieldText().contains("малако") }, "now: \(fieldText())")
    }

    // A fix reopens the popup on the next issue by itself; start the Skip step from a closed popup.
    E2E.key(kVK_Escape)
    E2E.pause(1.0)
    if let typo = wordRect("ощибка") {
        let count = E2E.underlineCount()
        E2E.click(CGPoint(x: typo.midX, y: typo.midY))
        if E2E.wait(4, { E2E.window("BindAll Fixes") != nil }), let popupRect = E2E.window("BindAll Fixes")?.bounds {
            // The popup above the word is entered with ↑, below it with ↓; the farthest choice is Skip.
            let above = popupRect.maxY <= typo.minY + 2
            let way = above ? kVK_UpArrow : kVK_DownArrow
            let since = Date()
            for _ in 0..<8 { E2E.key(way); E2E.pause(0.08) }
            E2E.allowBareReturn = true
            E2E.key(kVK_Return)
            E2E.allowBareReturn = false
            record("Skip (reached with the arrows) removes that underline",
                   E2E.wait(3) { E2E.underlineCount() < count } && E2E.hasEvent("proofread", "skipped", since: since),
                   "popup \(above ? "above" : "below"); underlines \(count) → \(E2E.underlineCount())")
        } else {
            record("Skip", false, "fixes popup did not open")
        }
    }

    // Skip moves the open popup on to the next issue; close it so the click lands on the word.
    E2E.key(kVK_Escape)
    E2E.wait(2) { E2E.window("BindAll Fixes") == nil }
    if let grammar = wordRect("граматика") {
        E2E.click(CGPoint(x: grammar.midX, y: grammar.midY))
        if E2E.wait(4, { E2E.window("BindAll Fixes") != nil }),
           let close = E2E.testElement(window: "BindAll Fixes", E2E.named("Close")),
           let frame = E2E.frame(close) {
            let panel = E2E.window("BindAll Fixes")?.bounds ?? .zero
            E2E.hoverThenClick(CGPoint(x: frame.midX, y: frame.midY))
            let first = E2E.wait(2) { E2E.window("BindAll Fixes") == nil }
            if !first {
                E2E.click(CGPoint(x: frame.midX, y: frame.midY))
                print("    cross: first click ignored, second \(E2E.wait(2) { E2E.window("BindAll Fixes") == nil } ? "worked" : "ignored too")")
            }
            record("the cross closes the fixes", first,
                   "button \(frame), panel \(panel)")
        } else {
            record("the cross closes the fixes", false, "popup or its Close button not found")
            try? E2E.dumpTestWindows("BindAll Fixes").write(to: outDir.appending(path: "fixes-tree.txt"), atomically: true, encoding: .utf8)
        }
    }
}

func fixAllScenario() {
    group = "Fix all"
    clearField()
    E2E.type("Вчера малако было свежее, а ощибка в слове и граматика тоже. ")
    guard E2E.wait(12, { E2E.underlineCount() >= 3 }), let word = wordRect("ощибка") else {
        record("Fix all", false, "underlines \(E2E.underlineCount())"); return
    }
    E2E.click(CGPoint(x: word.midX, y: word.midY))
    guard E2E.wait(4, { E2E.window("BindAll Fixes") != nil }) else { record("Fix all", false, "popup did not open"); return }
    let button = E2E.testElement(window: "BindAll Fixes") {
        ((E2E.attr($0, kAXDescriptionAttribute) as? String) ?? (E2E.attr($0, kAXTitleAttribute) as? String) ?? "").hasPrefix("Fix all")
    }
    record("the popup offers Fix all", button != nil)
    guard let button, let frame = E2E.frame(button) else { E2E.key(kVK_Escape); return }
    E2E.click(CGPoint(x: frame.midX, y: frame.midY))
    let preview = E2E.wait(4) { E2E.window("BindAll Preview") != nil }
    record("Fix all shows a preview", preview)
    guard preview else { return }
    E2E.allowBareReturn = true
    E2E.key(kVK_Return)
    E2E.allowBareReturn = false
    let fixed = E2E.wait(5) { !fieldText().contains("малако") && !fieldText().contains("ощибка") && !fieldText().contains("граматика") }
    record("Apply fixes every word at once", fixed, "now: \(fieldText())")
    record("the underlines go", E2E.wait(8) { E2E.underlineCount() == 0 }, "left \(E2E.underlineCount())")

    // ⌘Return from the popup does the same.
    clearField()
    E2E.type("Опять малако и ощибка здесь. ")
    if E2E.wait(12, { E2E.underlineCount() >= 2 }), let typo = wordRect("ощибка") {
        E2E.click(CGPoint(x: typo.midX, y: typo.midY))
        if E2E.wait(4, { E2E.window("BindAll Fixes") != nil }) {
            E2E.key(kVK_Return, .maskCommand)
            record("⌘Return in the popup opens the Fix all preview", E2E.wait(4) { E2E.window("BindAll Preview") != nil })
            if let close = E2E.testElement(window: "BindAll Preview", E2E.named("Cancel")) ?? E2E.testElement(window: "BindAll Preview", E2E.named("Close")) {
                E2E.press(close)
            } else {
                E2E.key(kVK_Escape)
            }
            E2E.wait(2) { E2E.window("BindAll Preview") == nil }
        }
    }
}

func dictionaryScenario() {
    group = "Dictionary"
    clearField()
    // A made-up word, so adding it cannot hide a typo another group relies on.
    E2E.type("Сегодня бзыграмка пришла и снова бзыграмка ушла. ")
    guard E2E.wait(20, { E2E.underlineCount() >= 2 }), let word = wordRect("бзыграмка") else {
        record("the made-up word is underlined", false, "underlines \(E2E.underlineCount())"); return
    }
    record("the made-up word is underlined", true, "underlines \(E2E.underlineCount())")
    E2E.click(CGPoint(x: word.midX, y: word.midY))
    guard E2E.wait(4, { E2E.window("BindAll Fixes") != nil }),
          let add = E2E.testElement(window: "BindAll Fixes", E2E.named("Add to dictionary")), let frame = E2E.frame(add) else {
        record("the popup offers Add to dictionary", false); E2E.key(kVK_Escape); return
    }
    record("the popup offers Add to dictionary", true)
    E2E.click(CGPoint(x: frame.midX, y: frame.midY))
    record("adding removes every underline on the word", E2E.wait(3) { E2E.underlineCount() == 0 },
           "left \(E2E.underlineCount())")
    E2E.key(kVK_Escape)
    focusTextEdit()
    E2E.key(kVK_DownArrow, .maskCommand) // the click left the caret inside the word
    // Unicode-only synthetic keys are dropped here until one with a real key code arrives (a
    // person's keys always carry one); → at the end of the text changes nothing.
    E2E.pause(0.5)
    E2E.key(kVK_RightArrow)
    E2E.type("Ещё раз Бзыграмка тут. ")
    E2E.pause(3)
    record("the word stays unflagged when typed again", fieldText().contains("Бзыграмка тут") && E2E.underlineCount() == 0,
           "underlines \(E2E.underlineCount()); text: \(fieldText())")
    if E2E.underlineCount() > 0 { snapshotField("dictionary-retyped") }
    let stored = Process()
    let pipe = Pipe()
    stored.executableURL = URL(fileURLWithPath: "/bin/sh")
    stored.arguments = ["-c", "defaults export com.evgeny.bindall.e2e - | python3 -c 'import plistlib,sys; sys.stdout.buffer.write(plistlib.loads(sys.stdin.buffer.read())[\"BindAll.settings.v1\"])'"]
    stored.standardOutput = pipe
    try? stored.run(); stored.waitUntilExit()
    let saved = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    record("the word is saved in the settings", saved.contains("бзыграмка"))
}

func historyScenario() {
    group = "History"
    guard let pid = E2E.testApp?.processIdentifier else { return }
    let app = AXUIElementCreateApplication(pid)
    func openStarMenu() -> Bool {
        E2E.key(kVK_ANSI_A, .maskCommand)
        // The field star moves to the selection a moment after ⌘A; read its place once it settled.
        E2E.pause(1.2)
        guard E2E.wait(4, { E2E.window("BindAll Star") != nil }), let star = E2E.window("BindAll Star")?.bounds else {
            print("    no star; windows \(E2E.windows().map(\.name)), text \(fieldText())")
            return false
        }
        E2E.click(CGPoint(x: star.midX, y: star.midY))
        E2E.pause(0.6)
        return true
    }
    func item(_ match: @escaping (String) -> Bool) -> AXUIElement? {
        var hit: AXUIElement?
        E2E.wait(1) {
            hit = E2E.find(in: app, depth: 8) { (E2E.attr($0, kAXTitleAttribute) as? String).map(match) ?? false }
            return hit != nil
        }
        return hit
    }
    func applyPreview() -> Bool {
        guard E2E.wait(15, { E2E.window("BindAll Preview") != nil }) else { return false }
        E2E.allowBareReturn = true
        E2E.key(kVK_Return)
        E2E.allowBareReturn = false
        return true
    }

    // A result to remember.
    clearField()
    E2E.type("Этот текст для звёздачки. ")
    E2E.pause(1.0)
    guard openStarMenu() else { record("History", false, "no star"); return }
    if let fix = item({ $0 == "Fix spelling" }) { E2E.press(fix) } else { pickMenuItem(downs: 2) }
    guard applyPreview(), E2E.wait(5, { !fieldText().contains("звёздачки") }) else { record("History", false, "Fix spelling did not apply"); return }
    let remembered = fieldText().trimmingCharacters(in: .whitespacesAndNewlines)

    clearField()
    E2E.type("Совсем другой текст. ")
    E2E.pause(1.0)
    guard openStarMenu() else { record("the star menu lists History", false, "no star"); return }
    // History is the last item; its newest entry is first in the submenu.
    if let history = item({ $0 == "History" }) {
        E2E.press(history)
        E2E.pause(0.5)
        if let entry = item({ $0.contains("звёздоч") }) { E2E.press(entry) } else { pickMenuItem() }
    } else {
        pickMenuItem(ups: 1, thenRight: true)
    }
    record("picking the newest History entry shows a preview", applyPreview())
    record("Apply puts the result in place", E2E.wait(5) { fieldText().trimmingCharacters(in: .whitespacesAndNewlines) == remembered },
           "now: \(fieldText()), expected: \(remembered)")
}

/// Picks an item of the open star menu with the keyboard (the menu is not always in the AX tree):
/// `downs` steps from the top, or `ups` from the bottom, then Return (the menu takes it, not the app).
func pickMenuItem(downs: Int = 0, ups: Int = 0, thenRight: Bool = false) {
    for _ in 0..<downs { E2E.key(kVK_DownArrow) }
    for _ in 0..<ups { E2E.key(kVK_UpArrow) }
    if thenRight { E2E.key(kVK_RightArrow); E2E.pause(0.3) }
    E2E.allowBareReturn = true
    E2E.key(kVK_Return)
    E2E.allowBareReturn = false
}

func explainScenario() {
    group = "Explain"
    guard let pid = E2E.testApp?.processIdentifier else { return }
    for (name, downs) in [("Explain", 6), ("Summarize", 7)] {
        clearField()
        let text = "Совещание переносится на четверг, потому что заказчик не успел прислать ТЗ. "
        E2E.type(text)
        E2E.pause(1.0)
        E2E.key(kVK_ANSI_A, .maskCommand)
        E2E.pause(1.2)
        guard let star = E2E.window("BindAll Star")?.bounds else { record(name, false, "no star"); continue }
        E2E.click(CGPoint(x: star.midX, y: star.midY))
        E2E.pause(0.6)
        let app = AXUIElementCreateApplication(pid)
        if let item = E2E.find(in: app, depth: 6, { (E2E.attr($0, kAXTitleAttribute) as? String) == name }) {
            E2E.press(item)
        } else {
            pickMenuItem(downs: downs)
        }
        let shown = E2E.wait(40) { E2E.window("BindAll Translation") != nil }
        var body = ""
        if shown, let panel = E2E.find(in: app, depth: 2, { (E2E.attr($0, kAXTitleAttribute) as? String) == "BindAll Translation" }) {
            body = E2E.dump(panel, depth: 12)
            E2E.snapshot(E2E.window("BindAll Translation")!.bounds, to: outDir.appending(path: "\(name.lowercased()).png"))
        }
        record("\(name) shows its result in a popup", shown && !body.contains("Error"), shown ? "" : "no popup")
        if let popup = E2E.window("BindAll Translation")?.bounds, let fieldFrame = textEditField().flatMap(E2E.frame) {
            let near = popup.minY >= fieldFrame.minY - 40 && popup.minY <= fieldFrame.maxY + 40
                || popup.maxY >= fieldFrame.minY - 40 && popup.maxY <= fieldFrame.minY + 40
                || fieldFrame.insetBy(dx: -10, dy: -10).contains(CGPoint(x: popup.midX, y: popup.midY))
            record("\(name): the window is by the field, on screen, at least 380 wide",
                   near && E2E.isOnScreen(popup) && popup.width >= 380, "popup \(popup), field \(fieldFrame)")
        }
        record("\(name) leaves the text alone", fieldText() == text, "now: \(fieldText())")
        E2E.key(kVK_Escape)
        let closed = E2E.wait(2) { E2E.window("BindAll Translation") == nil }
        record("\(name): Esc closes the window", closed, "front \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-")")
        if !closed { E2E.key(kVK_Escape) }
    }
}

func preSendScenario() {
    group = "Before sending"
    func warningUp() -> Bool {
        E2E.window("BindAll Fixes") != nil && E2E.dumpTestWindows("BindAll Fixes").contains("Return sends anyway")
    }
    func press(_ code: Int, _ flags: CGEventFlags = []) {
        E2E.allowBareReturn = true
        E2E.key(code, flags)
        E2E.allowBareReturn = false
    }
    clearField()
    E2E.type("Здесь малако осталось")
    guard E2E.wait(12, { E2E.underlineCount() >= 1 }) else { record("Before sending", false, "no underline"); return }
    let text = fieldText()

    press(kVK_Return)
    record("Return with an issue left shows the warning", E2E.wait(2) { warningUp() })
    record("…and is held back", fieldText() == text, "now: \(fieldText().debugDescription)")
    press(kVK_Escape)
    record("Esc takes the warning down, nothing sent", E2E.wait(2) { !warningUp() } && fieldText() == text)

    press(kVK_Return)
    _ = E2E.wait(2) { warningUp() }
    E2E.key(kVK_Tab)
    record("Tab opens the first issue", E2E.wait(3) { E2E.window("BindAll Fixes") != nil && !warningUp() } && fieldText() == text)
    press(kVK_Escape)
    E2E.wait(2) { E2E.window("BindAll Fixes") == nil }

    press(kVK_Return)
    _ = E2E.wait(2) { warningUp() }
    press(kVK_Return)
    record("Return again goes through", E2E.wait(2) { fieldText().hasSuffix("\n") }, "now: \(fieldText().debugDescription)")

    E2E.key(kVK_Delete)
    E2E.pause(0.5)
    press(kVK_Return, .maskShift)
    record("Shift+Return is never held", E2E.wait(2) { fieldText().hasSuffix("\n") } && !warningUp())
}

func translateInPlaceScenario() {
    group = "Translate in place"
    guard let pid = E2E.testApp?.processIdentifier else { return }
    clearField()
    E2E.type("Добрый день, коллеги")
    E2E.pause(1.0)
    E2E.key(kVK_ANSI_A, .maskCommand)
    E2E.pause(1.2)
    guard let star = E2E.window("BindAll Star")?.bounds else { record("Translate in place", false, "no star"); return }
    E2E.click(CGPoint(x: star.midX, y: star.midY))
    E2E.pause(0.6)
    if let item = E2E.find(in: AXUIElementCreateApplication(pid), depth: 6, { (E2E.attr($0, kAXTitleAttribute) as? String) == "Replace with translation" }) {
        E2E.press(item)
    } else {
        pickMenuItem(downs: 4)
    }
    let preview = E2E.wait(20) { E2E.window("BindAll Preview") != nil }
    record("it shows the translation in the preview", preview, preview ? "" : "windows \(E2E.windows().map(\.name))")
    record("nothing changes before Apply", fieldText() == "Добрый день, коллеги")
    guard preview else { return }
    E2E.allowBareReturn = true
    E2E.key(kVK_Return)
    E2E.allowBareReturn = false
    let latin = { fieldText().range(of: #"^[A-Za-z ,.!']+$"#, options: .regularExpression) != nil }
    record("Apply puts the translation in place", E2E.wait(5, latin), "now: \(fieldText())")
}

func voiceScenario() {
    group = "Push to Talk"
    clearField()
    E2E.key(kVK_RightArrow)

    E2E.rightOption(down: true)
    E2E.pause(0.1)
    E2E.rightOption(down: false)
    E2E.pause(1.5)
    record("a quick tap does nothing", fieldText().isEmpty && E2E.window("BindAll Voice") == nil)

    E2E.rightOption(down: true)
    E2E.key(kVK_ANSI_J)
    E2E.pause(0.6)
    E2E.rightOption(down: false)
    E2E.pause(1.0)
    record("Option with another key never records", E2E.window("BindAll Voice") == nil,
           "windows \(E2E.windows().map(\.name))")
    clearField()
    E2E.key(kVK_RightArrow)

    E2E.rightOption(down: true)
    let listening = E2E.wait(3) { E2E.window("BindAll Voice") != nil }
    record("holding the key shows the note", listening)
    E2E.pause(2.5)
    if let note = E2E.window("BindAll Voice") { E2E.snapshot(note.bounds, to: outDir.appending(path: "voice.png")) }
    E2E.rightOption(down: false)
    let typed = E2E.wait(15) { fieldText().lowercased().contains("проверка голосового ввода") }
    record("releasing types what was said", typed, "now: \(fieldText())")
    record("the note goes away", E2E.wait(3) { E2E.window("BindAll Voice") == nil })

    clearField()
    E2E.key(kVK_RightArrow)
    E2E.rightOption(down: true)
    _ = E2E.wait(3) { E2E.window("BindAll Voice") != nil }
    E2E.pause(2.5)
    E2E.rightOption(down: false, shift: true)
    let english = E2E.wait(20) {
        let text = fieldText()
        return !text.isEmpty && text.range(of: "[А-Яа-яЁё]", options: .regularExpression) == nil
            && text.lowercased().contains("voice")
    }
    record("with Shift it types the translation", english, "now: \(fieldText())")
}

func snapshotField(_ name: String) {
    if let el = textEditField(), let frame = E2E.frame(el) {
        E2E.snapshot(frame.intersection(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 160)),
                     to: outDir.appending(path: "\(name).png"))
    }
}

func starScenarios() {
    group = "Stars"
    clearField()
    E2E.type("Этот текст для звёздачки. ")
    E2E.pause(1.2)
    guard let field = textEditField().flatMap(E2E.frame) else { record("field frame", false); return }
    let star = E2E.wait(3) { E2E.window("BindAll Star") != nil }
    let starRect = E2E.window("BindAll Star")?.bounds ?? .zero
    record("the field star sits in the field's corner", star && field.insetBy(dx: -4, dy: -4).contains(starRect)
           && starRect.maxX > field.maxX - 60 && starRect.maxY > field.maxY - 60, "star \(starRect), field \(field)")

    E2E.key(kVK_ANSI_A, .maskCommand)
    E2E.pause(1.2)
    let stars = E2E.windows().filter { $0.name == "BindAll Star" }
    let moved = (stars.first?.bounds).map { !$0.equalTo(starRect) } ?? false
    record("a selection moves the star to it (one star only)", stars.count == 1 && moved, "stars \(stars.count)")
    snapshotField("star-selection")

    guard let starNow = E2E.window("BindAll Star")?.bounds else { return }
    E2E.click(CGPoint(x: starNow.midX, y: starNow.midY))
    E2E.pause(0.6)
    let pid = E2E.testApp!.processIdentifier
    let item = E2E.find(in: AXUIElementCreateApplication(pid), depth: 6) { (E2E.attr($0, kAXTitleAttribute) as? String) == "Fix spelling" }
    let menuUp = item != nil || E2E.windows().contains { $0.name.isEmpty && $0.bounds.height > 100 }
    record("clicking the star opens its menu", menuUp)
    if menuUp {
        if let item { E2E.press(item) } else { pickMenuItem(downs: 2) }
        let preview = E2E.wait(15) { E2E.window("BindAll Preview") != nil }
        if !preview {
            E2E.snapshot(CGRect(x: 100, y: 60, width: 900, height: 600), to: outDir.appending(path: "star-no-preview.png"))
            print("    windows: \(E2E.windows().map { "\($0.name) \($0.bounds)" }); used \(item == nil ? "keys" : "AX")")
        }
        record("Fix spelling shows a preview", preview)
        if let shown = E2E.window("BindAll Preview")?.bounds {
            record("the preview is on screen and at least 380 wide", E2E.isOnScreen(shown) && shown.width >= 380, "\(shown)")
        }
        if preview {
            E2E.snapshot(E2E.window("BindAll Preview")!.bounds, to: outDir.appending(path: "preview.png"))
            E2E.allowBareReturn = true
            E2E.key(kVK_Return)
            E2E.allowBareReturn = false
            record("Apply replaces the text", E2E.wait(5) { !fieldText().contains("звёздачки") }, "now: \(fieldText())")
        }
    }

    // Custom prompt panel stays on screen.
    focusTextEdit()
    E2E.key(kVK_RightArrow)
    E2E.pause(1.2)
    if let corner = E2E.window("BindAll Star")?.bounds {
        E2E.click(CGPoint(x: corner.midX, y: corner.midY))
        E2E.pause(0.6)
        if let custom = E2E.find(in: AXUIElementCreateApplication(pid), depth: 8, E2E.named("Custom prompt…")) {
            E2E.press(custom)
            let shown = E2E.wait(3) { E2E.window("BindAll Prompt") != nil }
            let rect = E2E.window("BindAll Prompt")?.bounds ?? .zero
            record("the custom prompt panel opens fully on screen", shown && E2E.isOnScreen(rect), "panel \(rect)")
            // A long prompt makes the window taller instead of scrolling inside two lines.
            let promptApp = AXUIElementCreateApplication(pid)
            if let field = E2E.find(in: promptApp, depth: 10, { (E2E.attr($0, kAXRoleAttribute) as? String) == "AXTextArea"
                || (E2E.attr($0, kAXRoleAttribute) as? String) == "AXTextField" }) {
                let long = Array(repeating: "Сделай текст короче и вежливее, сохрани смысл.", count: 5).joined(separator: " ")
                AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, long as CFString)
                E2E.type(" ", toPid: pid)
                E2E.pause(0.8)
                let grown = E2E.window("BindAll Prompt")?.bounds ?? .zero
                record("the prompt window grows with the text", grown.height > rect.height + 20 && E2E.isOnScreen(grown),
                       "\(rect.height) → \(grown.height)")
            }
            E2E.key(kVK_Escape)
            E2E.wait(2) { E2E.window("BindAll Prompt") == nil }
        } else {
            record("the custom prompt panel opens fully on screen", false, "menu item not found")
            try? E2E.dump(AXUIElementCreateApplication(pid), depth: 8).write(to: outDir.appending(path: "menu-tree.txt"), atomically: true, encoding: .utf8)
            E2E.key(kVK_Escape)
        }
    } else {
        record("the custom prompt panel opens fully on screen", false, "no field star after deselecting")
    }
}

func removeTellsScenario() {
    group = "Remove AI tells"
    clearField()
    E2E.type("Это — **важно** “очень”.\nLet me know if you have any questions!")
    E2E.key(kVK_ANSI_A, .maskCommand)
    E2E.pause(1.2)
    guard let star = E2E.window("BindAll Star")?.bounds else { record("star", false, "no selection star"); return }
    E2E.click(CGPoint(x: star.midX, y: star.midY))
    E2E.pause(0.6)
    let pid = E2E.testApp!.processIdentifier
    guard let item = E2E.find(in: AXUIElementCreateApplication(pid), depth: 6, { (E2E.attr($0, kAXTitleAttribute) as? String) == "Remove AI tells" }) else {
        record("menu item", false); E2E.key(kVK_Escape); return
    }
    E2E.press(item)
    let preview = E2E.wait(5) { E2E.window("BindAll Preview") != nil }
    record("a preview opens", preview)
    guard preview else { return }
    E2E.allowBareReturn = true
    E2E.key(kVK_Return)
    E2E.allowBareReturn = false
    let expected = "Это - важно \"очень\"."
    record("dash, Markdown, quotes and the sign-off are cleaned", E2E.wait(5) { fieldText() == expected }, "got \(fieldText().debugDescription)")
}

func quickTranslateScenario() {
    group = "Quick Translate"
    let pasteboard = NSPasteboard.general
    let saved = pasteboard.pasteboardItems?.map { item in item.types.map { ($0, item.data(forType: $0)) } } ?? []
    defer {
        pasteboard.clearContents()
        let items = saved.map { pairs -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in pairs { if let data { item.setData(data, forType: type) } }
            return item
        }
        pasteboard.writeObjects(items)
    }
    E2E.key(kVK_ANSI_E, [.maskCommand, .maskShift])
    let opened = E2E.wait(4) { E2E.window("BindAll Quick Translate") != nil }
    record("the shortcut opens Quick Translate", opened)
    guard opened else { return }
    E2E.pause(0.8)
    let pidQT = E2E.testApp!.processIdentifier
    let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
    // A synthesized shortcut does not count as user input for app activation, so the test clicks
    // into the field the way a person would.
    if let input = E2E.find(in: AXUIElementCreateApplication(pidQT), depth: 16, { (E2E.attr($0, kAXRoleAttribute) as? String) == "AXTextField" }),
       let frame = E2E.frame(input) {
        E2E.click(CGPoint(x: frame.midX, y: frame.midY))
        E2E.pause(0.3)
    }
    let focusNote = "frontmost before click: \(frontmost)"
    // SwiftUI fields take synthesized text unreliably (a person's real keys work); set it through
    // Accessibility, then a real key so the field registers the edit.
    if let input = E2E.find(in: AXUIElementCreateApplication(pidQT), depth: 16, { (E2E.attr($0, kAXRoleAttribute) as? String) == "AXTextField" }) {
        AXUIElementSetAttributeValue(input, kAXValueAttribute as CFString, "Добрый день, коллеги" as CFString)
        E2E.pause(0.2)
        E2E.key(kVK_End)
    }
    E2E.pause(0.3)
    let typedQT = E2E.find(in: AXUIElementCreateApplication(pidQT), depth: 16, { (E2E.attr($0, kAXRoleAttribute) as? String) == "AXTextField" }).map(E2E.value) ?? "?"
    print("    quick translate input after typing: \(typedQT.debugDescription)")
    if let w = E2E.window("BindAll Quick Translate") { E2E.snapshot(w.bounds, to: outDir.appending(path: "quick.png")) }
    print("    quick translate focus before typing: \(focusNote); TextEdit now: \(fieldText().debugDescription)")
    E2E.allowBareReturn = true
    E2E.key(kVK_Return)
    E2E.allowBareReturn = false
    E2E.pause(3)
    try? E2E.dumpTestWindows("BindAll Quick Translate").write(to: outDir.appending(path: "quick-tree.txt"), atomically: true, encoding: .utf8)
    let before = pasteboard.changeCount
    E2E.key(kVK_ANSI_C, .maskCommand)
    E2E.pause(0.5)
    let copied = pasteboard.changeCount != before ? (pasteboard.string(forType: .string) ?? "") : ""
    record("⌘C with nothing selected copies the whole translation", !copied.isEmpty && !copied.contains("Добрый"),
           "clipboard: \(copied.debugDescription)")
    let pid = E2E.testApp!.processIdentifier
    if let clear = E2E.find(in: AXUIElementCreateApplication(pid), depth: 16, E2E.named("Clear")) {
        E2E.press(clear)
        E2E.pause(0.4)
        let input = E2E.find(in: AXUIElementCreateApplication(pid), depth: 14) { (E2E.attr($0, kAXRoleAttribute) as? String) == "AXTextArea" || (E2E.attr($0, kAXRoleAttribute) as? String) == "AXTextField" }
        record("Clear empties the input", input.map(E2E.value)?.isEmpty ?? false)
    } else {
        record("Clear empties the input", false, "Clear button not found")
    }
    E2E.key(kVK_Escape)
    record("Esc closes it", E2E.wait(2) { E2E.window("BindAll Quick Translate") == nil })
}

func trayScenario() {
    group = "Tray menu"
    focusTextEdit()
    E2E.pause(1.2)
    guard E2E.window("BindAll Star") != nil else { skip("Stars item", "no star visible to toggle"); return }
    let pid = E2E.testApp!.processIdentifier
    func pressStars() -> Bool {
        guard let bar = E2E.attr(AXUIElementCreateApplication(pid), "AXExtrasMenuBar"),
              let item = (E2E.attr(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement])?.first else { return false }
        E2E.press(item)
        E2E.pause(0.6)
        guard let stars = E2E.find(in: item, depth: 4, { (E2E.attr($0, kAXTitleAttribute) as? String) == "Stars" }) else {
            E2E.key(kVK_Escape); return false
        }
        E2E.press(stars)
        E2E.pause(1.5)
        return true
    }
    guard pressStars() else { record("Stars item", false, "status item or its Stars entry not found"); return }
    record("Stars off hides the star", E2E.wait(2) { E2E.window("BindAll Star") == nil })
    _ = pressStars()
    focusTextEdit()
    E2E.type(" ")
    record("Stars on brings it back", E2E.wait(3) { E2E.window("BindAll Star") != nil })
}

// MARK: - Run

guard E2E.testApp != nil else { print("BindAll E2E is not running"); exit(2) }
let only = Set((ProcessInfo.processInfo.environment["E2E_ONLY"] ?? "").split(separator: ",").map(String.init))
let textEditGroups = ["autocomplete", "proofread", "fixAll", "dictionary", "history", "explain", "preSend", "translateInPlace", "voice", "stars", "removeTells", "quick", "tray"]
let needsTextEdit = only.isEmpty || !only.isDisjoint(with: textEditGroups)
func run(_ name: String, _ body: () -> Void) { if only.isEmpty || only.contains(name) { body() } }

if needsTextEdit {
    guard openTextEdit() else { print("could not open a TextEdit document"); exit(2) }
    // Accessibility for the test build: without it nothing reacts to typing.
    clearField()
    let probeStart = Date()
    E2E.type("Проверка доступа прив")
    if !E2E.wait(4, { !E2E.events(since: probeStart).isEmpty }) {
        print("BindAll E2E does not react: grant it Accessibility (System Settings → Privacy & Security → Accessibility) and run again.")
        exit(3)
    }
    run("autocomplete", autocompleteScenarios)
    run("proofread", proofreadScenarios)
    run("fixAll", fixAllScenario)
    run("dictionary", dictionaryScenario)
    run("history", historyScenario)
    run("explain", explainScenario)
    run("preSend", preSendScenario)
    run("translateInPlace", translateInPlaceScenario)
    run("voice", voiceScenario)
    run("stars", starScenarios)
    run("removeTells", removeTellsScenario)
    run("quick", quickTranslateScenario)
    run("tray", trayScenario)
    clearField()
    let close = Process()
    close.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    close.arguments = ["-e", "tell application \"TextEdit\" to close (every document whose name is \"\(docURL.lastPathComponent)\") saving no"]
    try? close.run(); close.waitUntilExit()
    try? FileManager.default.removeItem(at: docURL)
}
run("slack") { electronScenarios(slackTarget) }
run("claude") { electronScenarios(claudeTarget) }

var report = "# BindAll E2E\n\n| Group | Scenario | Result | Note |\n|---|---|---|---|\n"
for row in rows { report += "| \(row.group) | \(row.name) | \(row.status) | \(row.note.replacingOccurrences(of: "|", with: "/")) |\n" }
let failed = rows.filter { $0.status == "FAIL" }.count
report += "\n\(rows.count - failed) of \(rows.count) passed.\n"
try? report.write(to: outDir.appending(path: "report.md"), atomically: true, encoding: .utf8)
print("\n\(rows.count - failed)/\(rows.count) passed — \(outDir.appending(path: "report.md").path)")
exit(failed == 0 ? 0 : 1)
