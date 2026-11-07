import AppKit
import ApplicationServices
import Carbon.HIToolbox

// Slack and Claude: Electron editors with real accounts behind them. Nothing here ever sends: no
// bare Return is posted (the harness refuses it), fixes are applied by clicking, and the draft is
// emptied at the end.

struct ElectronTarget {
    let name: String
    let bundleID: String
    var allowsEscape = true
    /// Opens a fresh, empty composer and leaves the caret in it.
    let openComposer: (pid_t) -> Void
}

let slackTarget = ElectronTarget(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", allowsEscape: true) { pid in
    // "New message": a draft with no recipient yet, so even a stray send has nowhere to go.
    if isNewMessage(pid) { focusComposer(pid); return }
    E2E.key(kVK_ANSI_N, .maskCommand)
    E2E.pause(1.5)
    focusComposer(pid)
}

// Claude hosts the Claude Code session that may be driving this run, and Esc there stops it: the
// run types only into the composer of the window in front (prepared by hand) and never presses Esc.
let claudeTarget = ElectronTarget(name: "Claude", bundleID: "com.anthropic.claudefordesktop", allowsEscape: false) { pid in
    let app = AXUIElementCreateApplication(pid)
    guard let window = ((E2E.attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [])
        .first(where: { (E2E.attr($0, kAXMainAttribute) as? Bool) == true }) else { return }
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    var area: CGRect?
    collect(window, depth: 50) { el in
        if area == nil, isTextArea(el), E2E.value(el).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            area = E2E.frame(el)
        }
    }
    guard let area else { return }
    E2E.click(CGPoint(x: area.midX, y: area.midY))
    E2E.pause(0.5)
}

/// Slack's "New message" view: a "To:" combo box above the composer.
func isNewMessage(_ pid: pid_t) -> Bool {
    guard let window = E2E.attr(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute).map({ $0 as! AXUIElement }) else { return false }
    return E2E.find(in: window, depth: 40) { (E2E.attr($0, kAXRoleAttribute) as? String) == "AXComboBox" } != nil
}

func isTextArea(_ el: AXUIElement) -> Bool { (E2E.attr(el, kAXRoleAttribute) as? String) == "AXTextArea" }

func composer(of pid: pid_t) -> AXUIElement? {
    guard let el = E2E.focusedElement(of: pid), isTextArea(el) else { return nil }
    return el
}

/// Clicks into the lowest empty text area of the front window: the message box, not the recipient field.
func focusComposer(_ pid: pid_t) {
    if let el = composer(of: pid), E2E.value(el).isEmpty { return }
    let app = AXUIElementCreateApplication(pid)
    guard let window = E2E.attr(app, kAXFocusedWindowAttribute).map({ $0 as! AXUIElement }) else { return }
    var areas: [(AXUIElement, CGRect)] = []
    collect(window, depth: 40) { el in
        if isTextArea(el), E2E.value(el).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let frame = E2E.frame(el), frame.width > 100 { areas.append((el, frame)) }
    }
    guard let area = areas.max(by: { $0.1.maxY < $1.1.maxY }) else { print("    no empty text area in the front window"); return }
    E2E.click(CGPoint(x: area.1.midX, y: area.1.midY))
    E2E.pause(0.5)
    if composer(of: pid) == nil {
        // A click can land on the placeholder overlay; ask for focus directly.
        AXUIElementSetAttributeValue(area.0, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        E2E.pause(0.5)
    }
    let focused = E2E.focusedElement(of: pid).flatMap { E2E.attr($0, kAXRoleAttribute) as? String } ?? "none"
    print("    clicked text area \(area.1); focused now: \(focused)")
}

func collect(_ root: AXUIElement, depth: Int, _ visit: (AXUIElement) -> Void) {
    visit(root)
    guard depth > 0 else { return }
    for child in (E2E.attr(root, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { collect(child, depth: depth - 1, visit) }
}

func electronScenarios(_ target: ElectronTarget) {
    group = target.name
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first else {
        skip("all", "\(target.name) is not running"); return
    }
    let pid = app.processIdentifier
    // Electron builds its accessibility tree only for clients that ask for it.
    AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    app.activate()
    E2E.pause(1.0)
    target.openComposer(pid)
    guard let field = composer(of: pid), E2E.value(field).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        skip("all", "no empty composer in focus; nothing was typed"); return
    }
    let text = { composer(of: pid).map(E2E.value) ?? "" }
    func rect(_ word: String) -> CGRect? {
        guard let el = composer(of: pid) else { return nil }
        let range = (E2E.value(el) as NSString).range(of: word)
        guard range.location != NSNotFound else { return nil }
        if let box = E2E.bounds(range, in: el) { return box }
        // Chromium answers geometry on the text runs inside the field, not on the field itself.
        var hit: CGRect?
        collect(el, depth: 8) { child in
            guard hit == nil, (E2E.attr(child, kAXRoleAttribute) as? String) == "AXStaticText" else { return }
            let local = (E2E.value(child) as NSString).range(of: word)
            if local.location != NSNotFound { hit = E2E.bounds(local, in: child) }
        }
        return hit
    }
    defer {
        if target.allowsEscape { E2E.key(kVK_Escape); focusComposer(pid) }
        if composer(of: pid) != nil {
            E2E.key(kVK_ANSI_A, .maskCommand)
            E2E.key(kVK_Delete)
            E2E.pause(0.4)
        }
        record("the draft is left empty", text().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "left: \(text())")
    }

    // Closes whatever BindAll has open. Claude never gets Esc; ← does the job there.
    func dismiss() {
        if target.allowsEscape {
            E2E.key(kVK_Escape)
        } else {
            E2E.key(kVK_LeftArrow)
            E2E.wait(2) { E2E.window("BindAll Fixes") == nil && !suggestionsVisible() }
            E2E.key(kVK_RightArrow)
        }
        E2E.wait(2) { E2E.window("BindAll Fixes") == nil && !suggestionsVisible() }
        E2E.pause(0.6)
    }
    func clearComposer() {
        E2E.key(kVK_ANSI_A, .maskCommand)
        E2E.key(kVK_Delete)
        E2E.pause(0.6)
    }
    func openFixes(_ word: String) -> CGRect? {
        guard let box = rect(word) else { return nil }
        E2E.click(CGPoint(x: box.midX, y: box.midY))
        if E2E.wait(4, { E2E.window("BindAll Fixes") != nil }) { return box }
        E2E.click(CGPoint(x: box.midX, y: box.midY))
        let second = E2E.wait(4) { E2E.window("BindAll Fixes") != nil }
        print("    \(word): first click opened nothing, second \(second ? "did" : "did not either"); underlines \(E2E.underlineCount())")
        return second ? box : nil
    }

    // MARK: Proofread

    E2E.pause(0.5)
    // Skips are remembered per rule, word and nearby text for the whole run, in every app: each
    // target gets its own neighbours so an earlier group's Skip does not hide this one's typo.
    let joiner = target.name == "Slack" ? "и" : "да"
    let sentence = "Вот малако \(joiner) ощибка, граматика в тексте "
    E2E.wait(3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    E2E.type(sentence)
    E2E.pause(0.5)
    if !text().contains("граматика") {
        // Right after the switch from another app the first keys can land before the composer has focus.
        print("    first typing was lost; focusing the composer again")
        target.openComposer(pid)
        clearComposer()
        E2E.type(sentence)
        E2E.pause(0.5)
    }
    record("typing reaches the composer", text().contains("граматика"), "value: \(text())")

    let underlined = E2E.wait(15) { E2E.underlineCount() >= 3 }
    let wordBox = rect("малако")
    record("typos are underlined", underlined,
           "count \(E2E.underlineCount()); word rect \(wordBox.map { "\($0)" } ?? "none"); field \(E2E.frame(field) ?? .zero)")
    if let frame = E2E.frame(field) { E2E.snapshot(frame, to: outDir.appending(path: "\(target.name.lowercased())-underlines.png")) }

    let star = E2E.wait(3) { E2E.window("BindAll Star") != nil }
    let starRect = E2E.window("BindAll Star")?.bounds ?? .zero
    let fieldFrame = E2E.frame(field) ?? .zero
    record("the field star sits at the field's edge", star && fieldFrame.insetBy(dx: -40, dy: -40).contains(starRect)
           && starRect.minX > fieldFrame.maxX - 80, "star \(starRect), field \(fieldFrame)")

    if openFixes("малако") != nil {
        record("clicking an underlined word opens the fixes", true)
        let before = text()
        E2E.key(kVK_LeftArrow)
        record("← moves the caret and closes the fixes", E2E.wait(1.5) { E2E.window("BindAll Fixes") == nil } && text() == before)
        if target.name == "Slack", openFixes("малако") != nil {
            let tree = E2E.dumpTestWindows("BindAll Fixes")
            let counter = E2E.testElement(window: "BindAll Fixes") { el in
                ["AXValue", "AXValueDescription"].contains { key in
                    (E2E.attr(el, key) as? String)?.range(of: #"^\d+ of \d+$"#, options: .regularExpression) != nil
                }
            }.flatMap { (E2E.attr($0, "AXValueDescription") as? String) ?? (E2E.attr($0, kAXValueAttribute) as? String) }
            let total = counter.flatMap { Int($0.split(separator: " ").last ?? "") }
            record("\"N of M\" matches the underlines", total == E2E.underlineCount(),
                   "counter \(counter ?? "none"), underlines \(E2E.underlineCount())")
            if counter == nil { try? tree.write(to: outDir.appending(path: "slack-fixes-tree.txt"), atomically: true, encoding: .utf8) }
            record("no \"add a space\" suggestion", !tree.localizedCaseInsensitiveContains("пробел")
                   && !tree.localizedCaseInsensitiveContains("add a space"))
            dismiss()
        }
        if openFixes("малако") != nil,
           let row = E2E.testElement(window: "BindAll Fixes", E2E.named("молоко")), let frame = E2E.frame(row) {
            E2E.click(CGPoint(x: frame.midX, y: frame.midY))
            record("clicking a fix applies it", E2E.wait(5) { text().contains("молоко") && !text().contains("малако") },
                   "now: \(text())")
        } else {
            record("clicking a fix applies it", false, "no \"молоко\" row")
            try? E2E.dumpTestWindows("BindAll Fixes").write(
                to: outDir.appending(path: "\(target.name.lowercased())-fixes-tree.txt"), atomically: true, encoding: .utf8)
        }
        dismiss()
    } else {
        record("clicking an underlined word opens the fixes", false, wordBox == nil ? "no rect for the word" : "")
    }

    // Arrows go into the popup (↑ above the word, ↓ below) without touching the text; Skip by click,
    // since a bare Return here would send.
    E2E.pause(0.8)
    if let typo = openFixes("ощибка"), let popupRect = E2E.window("BindAll Fixes")?.bounds {
        let count = E2E.underlineCount()
        let before = text()
        let above = popupRect.maxY <= typo.minY + 2
        E2E.key(above ? kVK_UpArrow : kVK_DownArrow)
        E2E.pause(0.4)
        record("the arrow toward the popup enters it", E2E.window("BindAll Fixes") != nil && text() == before,
               "popup \(above ? "above" : "below"); windows \(E2E.windows().map(\.name)); text \(text() == before ? "same" : text())")
        let since = Date()
        if let skipButton = E2E.testElement(window: "BindAll Fixes", E2E.named("Skip this issue")), let frame = E2E.frame(skipButton) {
            E2E.click(CGPoint(x: frame.midX, y: frame.midY))
            record("Skip removes that underline",
                   E2E.wait(3) { E2E.underlineCount() < count } && E2E.hasEvent("proofread", "skipped", since: since),
                   "underlines \(count) → \(E2E.underlineCount())")
        } else {
            record("Skip removes that underline", false, "no Skip button")
        }
        dismiss()
    } else {
        record("the arrow toward the popup enters it", false, "fixes popup did not open")
    }

    // MARK: Stars

    if let word = rect("тексте") {
        E2E.doubleClick(CGPoint(x: word.midX, y: word.midY))
        E2E.pause(1.2)
        let stars = E2E.windows().filter { $0.name == "BindAll Star" }
        let near = stars.first.map { $0.bounds.insetBy(dx: -80, dy: -80).intersects(word) } ?? false
        record("selecting a word shows one star next to it", stars.count == 1 && near,
               "stars \(stars.map(\.bounds)), word \(word)")
        E2E.key(kVK_RightArrow)
    }

    clearComposer()
    E2E.type("Этот текст для звёздачки. ")
    E2E.pause(1.0)
    E2E.key(kVK_ANSI_A, .maskCommand)
    E2E.pause(1.2)
    if let starNow = E2E.window("BindAll Star")?.bounds, let testPid = E2E.testApp?.processIdentifier {
        E2E.click(CGPoint(x: starNow.midX, y: starNow.midY))
        E2E.pause(0.6)
        let item = E2E.find(in: AXUIElementCreateApplication(testPid), depth: 6) {
            (E2E.attr($0, kAXTitleAttribute) as? String) == "Fix spelling"
        }
        let menuUp = item != nil || E2E.windows().contains { $0.name.isEmpty && $0.bounds.height > 100 }
        record("clicking the star opens its menu", menuUp)
        if menuUp {
            if let item { E2E.press(item) } else { pickMenuItem(downs: 2) }
            let preview = E2E.wait(15) { E2E.window("BindAll Preview") != nil }
            record("Fix spelling shows a preview", preview)
            if preview, let apply = E2E.testElement(window: "BindAll Preview", E2E.named("Apply")), let frame = E2E.frame(apply) {
                E2E.click(CGPoint(x: frame.midX, y: frame.midY))
                record("Apply replaces the text", E2E.wait(6) { !text().contains("звёздачки") && text().contains("звёздоч") },
                       "now: \(text())")
            } else if preview {
                record("Apply replaces the text", false, "no Apply button")
            }
        }
    } else {
        record("clicking the star opens its menu", false, "no star on the selection")
    }

    // MARK: Summarize, closed with its own button

    clearComposer()
    E2E.type("Совещание переносится на четверг, потому что заказчик не успел прислать техническое задание. ")
    E2E.pause(1.0)
    E2E.key(kVK_ANSI_A, .maskCommand)
    E2E.pause(1.2)
    if pressTrayItem("Summarize selection") {
        let shown = E2E.wait(40) { E2E.window("BindAll Translation") != nil }
        record("Summarize shows its result", shown)
        if shown, let close = E2E.testElement(window: "BindAll Translation", E2E.named("Close")).flatMap(E2E.frame) {
            E2E.hoverThenClick(CGPoint(x: close.midX, y: close.midY))
            let closed = E2E.wait(2) { E2E.window("BindAll Translation") == nil }
            E2E.pause(1.0)
            let alive = !(E2E.testApp?.isTerminated ?? true)
            record("Close closes the summary and BindAll keeps running", closed && alive, "closed \(closed), running \(alive)")
            if !alive { return }
        }
    } else {
        record("Summarize shows its result", false, "no Summarize selection in the menu bar")
    }
    focusComposer(pid)

    // MARK: Fix all

    clearComposer()
    E2E.type("Снова малако \(joiner) граматика тут ")
    if E2E.wait(12, { E2E.underlineCount() >= 2 }), openFixes("граматика") != nil,
       let button = E2E.testElement(window: "BindAll Fixes", {
           ((E2E.attr($0, kAXDescriptionAttribute) as? String) ?? (E2E.attr($0, kAXTitleAttribute) as? String) ?? "").hasPrefix("Fix all")
       }) ?? nil, let frame = E2E.frame(button) {
        E2E.click(CGPoint(x: frame.midX, y: frame.midY))
        if E2E.wait(4, { E2E.window("BindAll Preview") != nil }),
           let apply = E2E.testElement(window: "BindAll Preview", E2E.named("Apply")), let applyFrame = E2E.frame(apply) {
            E2E.click(CGPoint(x: applyFrame.midX, y: applyFrame.midY))
            record("Fix all fixes every word at once", E2E.wait(6) { !text().contains("граматика") && !text().contains("малако") }, "now: \(text())")
        } else {
            record("Fix all fixes every word at once", false, "no preview")
        }
    } else {
        record("Fix all fixes every word at once", false, "no Fix all in the popup; underlines \(E2E.underlineCount())")
    }

    // MARK: Autocomplete

    focusComposer(pid)
    clearComposer()
    E2E.type("Сегодня мы обсуждали прив")
    let shown = E2E.wait(4) { suggestionsVisible() }
    record("a suggestion appears while typing", shown, shown ? "" : "windows: \(E2E.windows().map(\.name))")
    record("at the end of a line it is inline gray text", E2E.window("BindAll Inline") != nil,
           "shown as \(E2E.windows().map(\.name))")
    if let inline = E2E.window("BindAll Inline")?.bounds, let typed = rect("прив") {
        record("the gray text follows the caret", abs(inline.minX - typed.maxX) <= 2 && abs(inline.midY - typed.midY) < 8,
               "inline \(inline), word \(typed)")
    }
    let before = text()
    E2E.key(kVK_Tab)
    record("Tab accepts it", E2E.wait(2) { text().trimmingCharacters(in: .whitespacesAndNewlines).count > before.count },
           "now: \(text())")

    E2E.type(" прив")
    _ = E2E.wait(3) { suggestionsVisible() }
    let typed = text()
    E2E.key(kVK_LeftArrow)
    record("← moves the caret and closes the suggestion", E2E.wait(1.5) { !suggestionsVisible() } && text() == typed)
    E2E.key(kVK_RightArrow)

    E2E.type("е")
    _ = E2E.wait(3) { suggestionsVisible() }
    E2E.key(kVK_DownArrow)
    record("↓ opens the list from the gray text",
           E2E.wait(1.5) { E2E.window("BindAll Suggestions") != nil && E2E.window("BindAll Inline") == nil },
           "windows: \(E2E.windows().map(\.name))")
    dismiss()

    E2E.type(" конец")
    for _ in 0..<5 { E2E.key(kVK_LeftArrow) }
    E2E.type("прив")
    let midLine = E2E.wait(3) { E2E.window("BindAll Suggestions") != nil }
    record("in the middle of a line the list is shown", midLine && E2E.window("BindAll Inline") == nil,
           "windows: \(E2E.windows().map(\.name))")
    dismiss()

    // Several lines (Shift+Return, never a bare Return): still gray text on the last line.
    clearComposer()
    E2E.type("Первая строка\nВторая строка\nСегодня мы обсуждали прив")
    let multi = E2E.wait(4) { E2E.window("BindAll Inline") != nil }
    var note = "windows \(E2E.windows().map(\.name))"
    if let inline = E2E.window("BindAll Inline")?.bounds, let el = composer(of: pid) {
        var word: CGRect?
        collect(el, depth: 8) { child in
            guard word == nil, (E2E.attr(child, kAXRoleAttribute) as? String) == "AXStaticText" else { return }
            let local = (E2E.value(child) as NSString).range(of: "прив", options: .backwards)
            if local.location != NSNotFound, E2E.value(child).contains("обсуждали") { word = E2E.bounds(local, in: child) }
        }
        if let word { note = "inline \(inline), word \(word)" }
        record("on the third line it is still inline gray text", multi && (word.map { abs(inline.minX - $0.maxX) <= 2 && abs(inline.midY - $0.midY) < 8 } ?? false), note)
    } else {
        record("on the third line it is still inline gray text", false, note)
    }
    dismiss()

    // MARK: A long list

    // A message like a real one: numbered items, a nested list, several hundred characters. Editors
    // turn "1. " into list markup, which puts the text runs deeper in the tree than a flat paragraph.
    clearComposer()
    let items = [
        "1. Верни дизайн иконки звезды без толстых лучей",
        "2. Анимацию звезды как можем улучшить, нужно больше анимации",
        "3. Можем ли улучшить анимацию иконки в меню баре, какие варианты",
        "4. Добавь иконку микрофона при аудио записи",
        "5. Почему серый цвет предложений не появляется, пока я пишу",
        "6. Подчёркивание ошибок не работает, вот пока я пишу тоже",
        "7. Попап правок",
        "   1. Значок глаза при наведении синий, а книга серая",
        "   2. Кнопка сильно выделена, тут сабака \(joiner) ашибка рядом",
        "8. Сегодня мы обсуждали прив",
    ]
    E2E.type(items.joined(separator: "\n"))
    let long = text()
    let flat = long.replacingOccurrences(of: "\n", with: " ")
    print("    long message: \((long as NSString).length) UTF-16 units, \(long.components(separatedBy: "\n").count) lines in the value")
    if let el = composer(of: pid) {
        var leaves = 0, deepest = 0
        func walk(_ node: AXUIElement, _ depth: Int) {
            if (E2E.attr(node, kAXRoleAttribute) as? String) == "AXStaticText" { leaves += 1; deepest = max(deepest, depth) }
            guard depth < 12 else { return }
            for child in (E2E.attr(node, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(child, depth + 1) }
        }
        walk(el, 0)
        print("    composer tree: \(leaves) text runs, deepest at level \(deepest)")
    }
    record("the long list reaches the composer", flat.contains("обсуждали прив"), "value: \(long.prefix(80))…")
    let longInline = E2E.wait(4) { E2E.window("BindAll Inline") != nil }
    record("at the end of a long list it is inline gray text", longInline, "windows \(E2E.windows().map(\.name))")
    dismiss()
    E2E.type(" ")
    let nested = E2E.wait(15) { rect("сабака") != nil && E2E.underlineCount() >= 2 }
    record("typos in a nested item are underlined", nested, "underlines \(E2E.underlineCount())")
    if let frame = E2E.frame(field) { E2E.snapshot(frame, to: outDir.appending(path: "\(target.name.lowercased())-long-list.png")) }
    if openFixes("ашибка") != nil {
        record("a typo in a nested item opens its fixes", true)
        dismiss()
    } else {
        record("a typo in a nested item opens its fixes", false, "underlines \(E2E.underlineCount())")
    }
}
