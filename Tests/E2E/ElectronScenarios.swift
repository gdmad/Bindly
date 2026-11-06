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

    E2E.pause(0.5)
    E2E.type("Тут есть малако и ощибка в тексте ")
    E2E.pause(0.5)
    record("typing reaches the composer", text().contains("ощибка"), "value: \(text())")

    let underlined = E2E.wait(15) { E2E.underlineCount() >= 2 }
    let wordBox = rect("малако")
    record("typos are underlined", underlined,
           "count \(E2E.underlineCount()); word rect \(wordBox.map { "\($0)" } ?? "none"); field \(E2E.frame(field) ?? .zero)")
    if let frame = E2E.frame(field) { E2E.snapshot(frame, to: outDir.appending(path: "\(target.name.lowercased())-underlines.png")) }

    if let milk = wordBox {
        E2E.click(CGPoint(x: milk.midX, y: milk.midY))
        let popup = E2E.wait(4) { E2E.window("BindAll Fixes") != nil }
        record("clicking an underlined word opens the fixes", popup)
        if popup {
            if let row = E2E.testElement(window: "BindAll Fixes", E2E.named("молоко")), let frame = E2E.frame(row) {
                E2E.click(CGPoint(x: frame.midX, y: frame.midY))
                record("clicking a fix applies it", E2E.wait(5) { text().contains("молоко") && !text().contains("малако") },
                       "now: \(text())")
            } else {
                record("clicking a fix applies it", false, "no \"молоко\" row")
                try? E2E.dumpTestWindows("BindAll Fixes").write(
                    to: outDir.appending(path: "\(target.name.lowercased())-fixes-tree.txt"), atomically: true, encoding: .utf8)
            }
            if target.allowsEscape { E2E.key(kVK_Escape) }
            E2E.wait(2) { E2E.window("BindAll Fixes") == nil }
        }
    } else {
        record("word geometry", false, "\(target.name) gave no rect for the word")
    }

    if let word = rect("тексте") {
        E2E.doubleClick(CGPoint(x: word.midX, y: word.midY))
        E2E.pause(1.2)
        let stars = E2E.windows().filter { $0.name == "BindAll Star" }
        let near = stars.first.map { $0.bounds.insetBy(dx: -80, dy: -80).intersects(word) } ?? false
        record("selecting a word shows one star next to it", stars.count == 1 && near,
               "stars \(stars.map(\.bounds)), word \(word)")
        E2E.key(kVK_RightArrow)
    }
}
