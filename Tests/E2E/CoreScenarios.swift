import AppKit
import ApplicationServices
import Carbon.HIToolbox

// The main paths that had no end-to-end check: the ⌘C bursts, the star's translation, action key and
// custom prompt, cancelling with Esc, the master switch, the restored clipboard and the Settings window.

/// Presses an item of the test build's status menu by title; false when the menu or item is not found.
@discardableResult
func pressTrayItem(_ title: String) -> Bool {
    guard let pid = E2E.testApp?.processIdentifier,
          let bar = E2E.attr(AXUIElementCreateApplication(pid), "AXExtrasMenuBar"),
          let item = (E2E.attr(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement])?.first else { return false }
    E2E.press(item)
    E2E.pause(0.6)
    // Items with a shortcut draw it into their title, so match the start of it.
    guard let entry = E2E.find(in: item, depth: 4, { (E2E.attr($0, kAXTitleAttribute) as? String)?.hasPrefix(title) ?? false }) else {
        E2E.key(kVK_Escape); return false
    }
    E2E.press(entry)
    E2E.pause(1.0)
    return true
}

/// Opens the star's menu on the whole text and picks `title` (by AX, or `downs` steps of the keyboard).
func runStarItem(_ title: String, downs: Int) -> Bool {
    guard let pid = E2E.testApp?.processIdentifier else { return false }
    let before = E2E.window("BindAll Star")?.bounds
    E2E.key(kVK_ANSI_A, .maskCommand)
    // The star moves from the field's corner to the selection; wait for that, not just for a star.
    guard E2E.wait(3, { E2E.window("BindAll Star").map { $0.bounds != before } ?? false }) || E2E.window("BindAll Star") != nil,
          let star = E2E.window("BindAll Star")?.bounds else {
        print("    \(title): no star; windows \(E2E.windows().map(\.name))")
        return false
    }
    E2E.pause(0.3)
    let current = E2E.window("BindAll Star")?.bounds ?? star
    E2E.click(CGPoint(x: current.midX, y: current.midY))
    E2E.pause(0.6)
    if let item = E2E.find(in: AXUIElementCreateApplication(pid), depth: 6, { (E2E.attr($0, kAXTitleAttribute) as? String) == title }) {
        E2E.press(item)
    } else {
        print("    \(title): not in the AX menu, picking with the keyboard")
        pickMenuItem(downs: downs)
    }
    return true
}

/// Clicks a button of a BindAll window by its name.
@discardableResult
func clickButton(_ name: String, in window: String) -> Bool {
    guard let frame = E2E.testElement(window: window, E2E.named(name)).flatMap(E2E.frame) else { return false }
    E2E.hoverThenClick(CGPoint(x: frame.midX, y: frame.midY))
    return true
}

/// Changed, has letters, and none of them lowercase: what "make it uppercase" leaves.
func isShouting(_ text: String, not original: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed != original && trimmed.contains(where: \.isLetter) && trimmed == trimmed.uppercased()
}

func isAlive() -> Bool { !(E2E.testApp?.isTerminated ?? true) }

// MARK: - ⌘C bursts

func hotkeyScenarios() {
    group = "Shortcuts"
    // ⌘C ⌘C: Fix selection, written straight back (no preview from shortcuts by default).
    clearField()
    E2E.type("Этот текст для звёздачки.")
    E2E.pause(1.0)
    E2E.key(kVK_ANSI_A, .maskCommand)
    E2E.pause(0.3)
    E2E.key(kVK_ANSI_C, .maskCommand)
    E2E.pause(0.08)
    E2E.key(kVK_ANSI_C, .maskCommand)
    let fixed = E2E.wait(20) { !fieldText().contains("звёздачки") && fieldText().contains("звёзд") }
    record("⌘C ⌘C fixes the selection in place", fixed, "now: \(fieldText())")

    // Nothing selected: ⌘C copies nothing, and what was on the clipboard is not the selection.
    clearField()
    let untouched = "Тут ничего не выделено."
    E2E.type(untouched)
    E2E.pause(1.0)
    E2E.key(kVK_RightArrow)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("старый буфер с ошибкой в слове малако", forType: .string)
    E2E.key(kVK_ANSI_C, .maskCommand)
    E2E.pause(0.08)
    E2E.key(kVK_ANSI_C, .maskCommand)
    let told = E2E.wait(5) { E2E.window("BindAll Translation") != nil && E2E.dumpTestWindows("BindAll Translation").contains("No text selected") }
    record("⌘C ⌘C with nothing selected says so", told, "windows \(E2E.windows().map(\.name))")
    record("…and pastes nothing", fieldText() == untouched, "now: \(fieldText())")
    if E2E.window("BindAll Translation") != nil { clickButton("Close", in: "BindAll Translation") }
    E2E.wait(2) { E2E.window("BindAll Translation") == nil }

    // A whole line selected with its line break: the fixed line keeps it.
    clearField()
    E2E.type("Перва строчка с ашибкой.")
    E2E.allowBareReturn = true
    E2E.key(kVK_Return)
    E2E.allowBareReturn = false
    E2E.type("Вторая строка.")
    E2E.pause(1.0)
    E2E.key(kVK_UpArrow, .maskCommand)
    E2E.key(kVK_DownArrow, .maskShift)
    E2E.pause(0.3)
    E2E.key(kVK_ANSI_C, .maskCommand)
    E2E.pause(0.08)
    E2E.key(kVK_ANSI_C, .maskCommand)
    let lineFixed = E2E.wait(20) { !fieldText().contains("ашибкой") }
    let lines = fieldText().components(separatedBy: "\n")
    record("a fixed line keeps its line break", lineFixed && lines.count == 2 && lines[1] == "Вторая строка.",
           "now: \(fieldText().debugDescription)")

    // ⌘C ⌘C ⌘C: the translation in a window, the text left alone.
    clearField()
    let original = "Добрый вечер, друзья."
    E2E.type(original)
    E2E.pause(1.0)
    E2E.key(kVK_ANSI_A, .maskCommand)
    E2E.pause(0.3)
    for _ in 0..<3 { E2E.key(kVK_ANSI_C, .maskCommand); E2E.pause(0.08) }
    let shown = E2E.wait(20) { E2E.window("BindAll Translation") != nil }
    let body = shown ? E2E.dumpTestWindows("BindAll Translation") : ""
    record("⌘C ⌘C ⌘C shows the translation in a window", shown && body.range(of: "[A-Za-z]{4}", options: .regularExpression) != nil,
           shown ? "" : "windows \(E2E.windows().map(\.name))")
    record("…and leaves the text alone", fieldText() == original, "now: \(fieldText())")
    if shown { clickButton("Close", in: "BindAll Translation") }
    record("its Close button closes it", E2E.wait(2) { E2E.window("BindAll Translation") == nil } && isAlive())

    // Restore clipboard (on in the test build): after a star action replaced the text, what was on
    // the clipboard before is back.
    clearField()
    E2E.type("Ещё один текст для звёздачки. ")
    E2E.pause(1.0)
    let marker = "e2e clipboard marker \(Int(Date().timeIntervalSince1970))"
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(marker, forType: .string)
    guard runStarItem("Fix spelling (LanguageTool)", downs: 2), E2E.wait(15, { E2E.window("BindAll Preview") != nil }) else {
        record("Restore clipboard: Fix spelling opens its preview", false); return
    }
    E2E.allowBareReturn = true
    E2E.key(kVK_Return)
    E2E.allowBareReturn = false
    _ = E2E.wait(5) { !fieldText().contains("звёздачки") }
    E2E.pause(1.0)
    record("the clipboard is restored after the text is replaced", NSPasteboard.general.string(forType: .string) == marker,
           "clipboard: \(NSPasteboard.general.string(forType: .string)?.prefix(40) ?? "empty")")
}

// MARK: - More of the star's menu

func starActionScenarios() {
    group = "Star actions"
    // Show translation: a window, nothing replaced.
    clearField()
    let original = "Спасибо за помощь."
    E2E.type(original)
    E2E.pause(1.0)
    if runStarItem("Show translation", downs: 3) {
        let shown = E2E.wait(20) { E2E.window("BindAll Translation") != nil }
        record("Show translation opens the translation window", shown, shown ? "" : "windows \(E2E.windows().map(\.name))")
        record("…and leaves the text alone", fieldText() == original, "now: \(fieldText())")
        if shown { clickButton("Close", in: "BindAll Translation") }
        E2E.wait(2) { E2E.window("BindAll Translation") == nil }
    } else {
        record("Show translation opens the translation window", false, "no selection star")
    }

    // A built-in action key.
    clearField()
    E2E.type("a quiet line of text")
    E2E.pause(1.0)
    if runStarItem("UPPERCASE", downs: 6) {
        let preview = E2E.wait(20) { E2E.window("BindAll Preview") != nil }
        record("an action key from the star shows a preview", preview)
        if preview {
            clickButton("Apply", in: "BindAll Preview")
            record("Apply writes the action key's result", E2E.wait(6) { isShouting(fieldText(), not: "a quiet line of text") },
                   "now: \(fieldText())")
        }
    } else {
        record("an action key from the star shows a preview", false, "no selection star")
    }

    // Custom prompt, all the way to the result.
    clearField()
    E2E.type("привет, завтра встреча в 10")
    E2E.pause(1.0)
    guard runStarItem("Custom prompt…", downs: 11), E2E.wait(3, { E2E.window("BindAll Prompt") != nil }) else {
        record("Custom prompt: its window opens", false); E2E.key(kVK_Escape); return
    }
    let promptPid = E2E.testApp!.processIdentifier
    if let input = E2E.find(in: AXUIElementCreateApplication(promptPid), depth: 10, {
        ["AXTextArea", "AXTextField"].contains((E2E.attr($0, kAXRoleAttribute) as? String) ?? "") }) {
        AXUIElementSetAttributeValue(input, kAXValueAttribute as CFString, "Напиши всё заглавными буквами" as CFString)
    }
    // A real key afterwards, so the field's binding takes the value.
    E2E.type(" ", toPid: promptPid)
    E2E.pause(0.4)
    E2E.allowBareReturn = true
    E2E.key(kVK_Return)
    E2E.allowBareReturn = false
    let preview = E2E.wait(25) { E2E.window("BindAll Preview") != nil }
    record("a custom prompt leads to a preview", preview, preview ? "" : "windows \(E2E.windows().map(\.name))")
    if preview {
        clickButton("Apply", in: "BindAll Preview")
        // The on-device model words things its own way; what is checked is that the instruction was followed.
        record("Apply writes the custom prompt's result", E2E.wait(6) { isShouting(fieldText(), not: "привет, завтра встреча в 10") },
               "now: \(fieldText())")
    }
}

// MARK: - Esc cancels a running action

func cancelScenario() {
    group = "Cancel"
    clearField()
    E2E.type("Совещание переносится на четверг, потому что заказчик не успел прислать ТЗ. ")
    E2E.pause(1.0)
    E2E.key(kVK_ANSI_A, .maskCommand)
    E2E.pause(1.2)
    guard pressTrayItem("Explain selection") else { record("setup: Explain selection is in the menu bar", false); return }
    // Esc while it runs, not before: the working star says it has started.
    let started = E2E.wait(4, step: 0.02) { (E2E.window("BindAll Star")?.bounds.width ?? 0) > 26 }
    guard started else { record("setup: the action starts", false, "windows \(E2E.windows().map(\.name))"); return }
    E2E.key(kVK_Escape)
    let neverShown = !E2E.wait(6) { E2E.window("BindAll Translation") != nil }
    record("Esc right after starting an action cancels it", neverShown && isAlive(),
           "windows \(E2E.windows().map(\.name))")
    if !neverShown { clickButton("Close", in: "BindAll Translation") }
    let idle = E2E.wait(3) { (E2E.window("BindAll Star")?.bounds.width ?? 0) < 26 }
    record("the star is idle again", idle, "star \(E2E.window("BindAll Star").map { "\($0.bounds)" } ?? "hidden")")
    focusTextEdit()
    E2E.key(kVK_ANSI_A, .maskCommand)
    E2E.pause(1.2)
    if pressTrayItem("Explain selection") {
        let shown = E2E.wait(30) { E2E.window("BindAll Translation") != nil }
        record("the next action still runs", shown)
        if shown { clickButton("Close", in: "BindAll Translation") }
        E2E.wait(2) { E2E.window("BindAll Translation") == nil }
    }
}

// MARK: - Master switch

/// Mean brightness of the test build's tray icon (0...1), from a screenshot of it.
func trayBrightness() -> Double? {
    guard let rect = trayIconRect() else { return nil }
    let file = outDir.appending(path: "tray-\(UUID().uuidString.prefix(6)).png")
    captureExact(rect, to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    guard let rep = NSBitmapImageRep(data: (try? Data(contentsOf: file)) ?? Data()) else { return nil }
    var sum = 0.0, count = 0.0
    for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        sum += Double(max(c.redComponent, c.greenComponent, c.blueComponent)); count += 1
    } }
    return count > 0 ? sum / count : nil
}

func masterSwitchScenario() {
    group = "Master switch"
    focusTextEdit()
    let bright = trayBrightness()
    guard pressTrayItem("Enabled") else { record("setup: the status menu's Enabled item is found", false); return }
    defer { if !isEnabledNow { pressTrayItem("Enabled") } }
    isEnabledNow = false
    clearField()
    E2E.type("Тут малако и сегодня мы обсуждали прив")
    E2E.pause(4)
    record("off: no underlines, no star, no suggestions",
           E2E.underlineCount() == 0 && E2E.window("BindAll Star") == nil && !suggestionsVisible(),
           "underlines \(E2E.underlineCount()), windows \(E2E.windows().map(\.name))")
    if let bright, let dim = trayBrightness() {
        // The dimming is relative: light and dark menu bars differ, the difference does not.
        record("off: the tray icon is dimmed", abs(dim - bright) > 0.01, String(format: "brightness %.3f → %.3f", bright, dim))
    }
    // A menu item is a click, not a trigger: it still runs while off.
    clearField()
    E2E.type("Совещание переносится на четверг. ")
    E2E.pause(0.5)
    E2E.key(kVK_ANSI_A, .maskCommand)
    E2E.pause(0.5)
    if pressTrayItem("Translate selection") {
        let shown = E2E.wait(20) { E2E.window("BindAll Translation") != nil }
        record("off: a menu-bar item still runs", shown)
        if shown { clickButton("Close", in: "BindAll Translation") }
        E2E.wait(2) { E2E.window("BindAll Translation") == nil }
    }
    focusTextEdit()
    // The star's editing actions on the selection from the menu bar, without a star.
    clearField()
    E2E.type("Тут малако в тексте. ")
    E2E.pause(0.5)
    E2E.key(kVK_ANSI_A, .maskCommand)
    E2E.pause(0.5)
    if pressTrayItem("Fix spelling") {
        let preview = E2E.wait(15) { E2E.window("BindAll Preview") != nil }
        record("off: Fix spelling from the menu bar previews the selection", preview)
        if preview {
            E2E.allowBareReturn = true
            E2E.key(kVK_Return)
            E2E.allowBareReturn = false
            record("…and Apply fixes it", E2E.wait(5) { fieldText().contains("молоко") }, "now: \(fieldText())")
        }
    } else {
        record("off: Fix spelling is in the menu bar", false)
    }
    guard pressTrayItem("Enabled") else { record("on again: the Enabled item is found", false); return }
    isEnabledNow = true
    clearField()
    E2E.type("Тут малако и снова текст ")
    record("on again: typos are underlined", E2E.wait(15) { E2E.underlineCount() >= 1 }, "underlines \(E2E.underlineCount())")
}
var isEnabledNow = true

// MARK: - Settings window

func settingsScenario() {
    group = "Settings"
    guard let pid = E2E.testApp?.processIdentifier else { return }
    guard pressTrayItem("Settings…") else { record("the status menu opens Settings", false); return }
    let app = AXUIElementCreateApplication(pid)
    func window() -> AXUIElement? {
        ((E2E.attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []).first { (E2E.attr($0, kAXTitleAttribute) as? String) == "BindAll Settings" }
    }
    let opened = E2E.wait(4) { window() != nil }
    record("the status menu opens Settings", opened)
    guard opened, let settings = window() else { return }
    let tabs = ["General", "Shortcuts", "AI Actions", "Translation", "Autocomplete", "Proofread", "Voice", "Providers"]
    var failed: [String] = []
    for tab in tabs {
        guard let button = E2E.find(in: settings, depth: 14, { E2E.named(tab)($0) && (E2E.attr($0, kAXRoleAttribute) as? String) == "AXButton" }) else {
            failed.append("\(tab): no tab button"); continue
        }
        E2E.press(button)
        E2E.pause(0.7)
        var elements = 0
        if let current = window() { collect(current, depth: 25) { _ in elements += 1 } }
        if !isAlive() { failed.append("\(tab): BindAll stopped"); break }
        if elements < 25 { failed.append("\(tab): \(elements) elements") }
    }
    record("every tab opens and shows its settings", failed.isEmpty, failed.joined(separator: "; "))
    if let frame = E2E.frame(settings) { E2E.snapshot(frame, to: outDir.appending(path: "settings.png")) }
    if let close = E2E.attr(settings, kAXCloseButtonAttribute) { E2E.press(close as! AXUIElement) }
    record("the window closes and BindAll keeps running", E2E.wait(3) { window() == nil } && isAlive())
}

// MARK: - Every window can be dragged

/// Drags `name` by its header and by its bottom margin; true when both moved it.
/// `headerY`: how far down the header's free area is (Quick Translate's top bar is all pickers but its
/// 12 pt padding).
func dragsBy(_ name: String, headerY: CGFloat = 22) -> (header: Bool, margin: Bool, detail: String) {
    guard let start = E2E.window(name)?.bounds else { return (false, false, "no window") }
    E2E.drag(from: CGPoint(x: start.minX + 40, y: start.minY + headerY), to: CGPoint(x: start.minX + 100, y: start.minY + 62))
    E2E.pause(0.4)
    let afterHeader = E2E.window(name)?.bounds ?? start
    // Moved the way it was pulled; the system may round or snap the last few points.
    let header = afterHeader.minX - start.minX > 40 && afterHeader.minY - start.minY > 25
    E2E.drag(from: CGPoint(x: afterHeader.minX + 40, y: afterHeader.maxY - 5), to: CGPoint(x: afterHeader.minX - 20, y: afterHeader.maxY - 45))
    E2E.pause(0.4)
    let afterMargin = E2E.window(name)?.bounds ?? afterHeader
    let margin = afterHeader.minX - afterMargin.minX > 40 && afterHeader.minY - afterMargin.minY > 25
    return (header, margin, "start \(start), after header \(afterHeader), after margin \(afterMargin)")
}

func dragScenario() {
    group = "Drag"
    func check(_ name: String, _ title: String, headerY: CGFloat = 22) {
        let moved = dragsBy(name, headerY: headerY)
        record("\(title): dragged by its header", moved.header, moved.detail)
        record("\(title): dragged by its margin", moved.margin, moved.detail)
    }

    // The result window.
    clearField()
    let text = "Совещание переносится на четверг. "
    E2E.type(text)
    E2E.pause(0.5)
    E2E.key(kVK_ANSI_A, .maskCommand)
    E2E.pause(0.5)
    if pressTrayItem("Explain selection"), E2E.wait(40, { E2E.window("BindAll Translation") != nil }) {
        E2E.pause(0.5)
        check("BindAll Translation", "the result window")
        record("…and its Close still works", clickButton("Close", in: "BindAll Translation") && E2E.wait(2) { E2E.window("BindAll Translation") == nil })
    } else {
        record("setup: Explain opens its window", false)
    }

    // The preview, and its Changes / Result switch still switches.
    focusTextEdit()
    clearField()
    E2E.type("Тут малако в тексте. ")
    E2E.pause(1.0)
    if runStarItem("Fix spelling (LanguageTool)", downs: 2), E2E.wait(15, { E2E.window("BindAll Preview") != nil }) {
        E2E.pause(0.5)
        check("BindAll Preview", "the preview")
        let result = E2E.testElement(window: "BindAll Preview", E2E.named("Result")).flatMap(E2E.frame)
        if let result { E2E.click(CGPoint(x: result.midX, y: result.midY)) }
        E2E.pause(0.4)
        // On Result the text shows without the struck-out word.
        let switched = E2E.wait(2) { !E2E.dumpTestWindows("BindAll Preview").contains("малако") }
        record("…its Changes / Result switch still takes clicks", result != nil && switched)
        E2E.key(kVK_Escape)
        E2E.wait(2) { E2E.window("BindAll Preview") == nil }
        record("…and the text is as it was", fieldText().contains("малако"), "now: \(fieldText())")
    } else {
        record("setup: Fix spelling opens the preview", false)
    }

    // The custom prompt (a second try: the star can still be settling after the preview).
    focusTextEdit()
    E2E.pause(1.0)
    let promptOpened = (1...2).contains { _ in
        runStarItem("Custom prompt…", downs: 11) && E2E.wait(3, { E2E.window("BindAll Prompt") != nil })
    }
    if promptOpened {
        E2E.pause(0.5)
        check("BindAll Prompt", "the custom prompt")
        E2E.key(kVK_Escape)
        E2E.wait(2) { E2E.window("BindAll Prompt") == nil }
    } else {
        record("setup: Custom prompt opens", false)
    }

    // Quick Translate.
    E2E.key(kVK_ANSI_E, [.maskCommand, .maskShift])
    if E2E.wait(4, { E2E.window("BindAll Quick Translate") != nil }) {
        E2E.pause(0.8)
        check("BindAll Quick Translate", "Quick Translate", headerY: 5)
        E2E.key(kVK_Escape)
        E2E.wait(2) { E2E.window("BindAll Quick Translate") == nil }
    } else {
        record("setup: Quick Translate opens", false)
    }
    focusTextEdit()
}
