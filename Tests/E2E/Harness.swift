import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Low-level helpers for driving apps and reading the test build's windows. Nothing here sends a
/// bare Return: in chat apps that sends the message.
enum E2E {
    static let testBundleID = "com.evgeny.bindall.e2e"

    // MARK: Waiting

    static func pause(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    @discardableResult
    static func wait(_ timeout: Double, step: Double = 0.15, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            pause(step)
        }
        return condition()
    }

    // MARK: Keyboard and mouse

    static func key(_ code: Int, _ flags: CGEventFlags = []) {
        precondition(!(code == kVK_Return && flags.isEmpty) || allowBareReturn, "a bare Return is never sent")
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)!
            event.flags = flags
            event.post(tap: .cghidEventTap)
            usleep(8_000)
        }
        usleep(40_000)
    }

    /// Only for native editors (TextEdit), where Return is a newline, not "send".
    nonisolated(unsafe) static var allowBareReturn = false

    static func type(_ text: String, perCharacter delay: useconds_t = 25_000) {
        for character in text {
            if character == "\n" { key(kVK_Return, .maskShift); continue }
            let units = Array(String(character).utf16)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.post(tap: .cghidEventTap)
                usleep(6_000)
            }
            usleep(delay)
        }
    }

    /// Typing into one of the test build's own SwiftUI fields: they ignore Unicode-only events from
    /// the global queue (a person's real keys work), so the events go straight to the process.
    static func type(_ text: String, toPid pid: pid_t) {
        for character in text {
            let units = Array(String(character).utf16)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.postToPid(pid)
                usleep(6_000)
            }
            usleep(20_000)
        }
    }

    /// `point` in Quartz screen coordinates (top-left origin).
    static func click(_ point: CGPoint) {
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            usleep(60_000)
        }
    }

    /// Moves the pointer there first, the way a person reaches a button before clicking it.
    static func hoverThenClick(_ point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        pause(0.3)
        click(point)
    }

    static func doubleClick(_ point: CGPoint) {
        for state in [1, 2] {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
                event?.setIntegerValueField(.mouseEventClickState, value: Int64(state))
                event?.post(tap: .cghidEventTap)
                usleep(30_000)
            }
        }
    }

    /// The right Option key alone, as a modifier change (`kVK_RightOption`, device bit for "right").
    /// The right Command key alone (`kVK_RightCommand`, device bit 0x10).
    static func rightCommand(down: Bool) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 54, keyDown: down)!
        event.type = .flagsChanged
        event.flags = down ? [.maskCommand, CGEventFlags(rawValue: 0x10)] : []
        event.post(tap: .cghidEventTap)
        usleep(20_000)
    }

    static func rightOption(down: Bool, shift: Bool = false) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 61, keyDown: down)!
        event.type = .flagsChanged
        var flags: CGEventFlags = down ? [.maskAlternate, CGEventFlags(rawValue: 0x40)] : []
        if shift { flags.insert(.maskShift) }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        usleep(20_000)
    }

    // MARK: Accessibility

    static func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func focusedElement(of pid: pid_t) -> AXUIElement? {
        attr(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute).map { $0 as! AXUIElement }
    }

    static func value(_ element: AXUIElement) -> String { attr(element, kAXValueAttribute) as? String ?? "" }

    /// Quartz rect of `range` in `element`.
    static func bounds(_ range: NSRange, in element: AXUIElement) -> CGRect? {
        var cf = CFRange(location: range.location, length: range.length)
        guard let param = AXValueCreate(.cfRange, &cf) else { return nil }
        var out: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         param, &out) == .success,
              let out, CFGetTypeID(out) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        AXValueGetValue(out as! AXValue, .cgRect, &rect)
        return rect.width > 0 && rect.height > 0 ? rect : nil
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = attr(element, kAXPositionAttribute), let s = attr(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    /// Depth-first search of `root` for the first element matching `match`.
    static func find(in root: AXUIElement, depth: Int = 12, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
        if match(root) { return root }
        guard depth > 0 else { return nil }
        for child in (attr(root, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            if let hit = find(in: child, depth: depth - 1, match) { return hit }
        }
        return nil
    }

    static func press(_ element: AXUIElement) { AXUIElementPerformAction(element, kAXPressAction as CFString) }

    // MARK: The test build

    static var testApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: testBundleID).first
    }

    struct Window {
        let name: String
        /// Quartz screen coordinates.
        let bounds: CGRect
    }

    /// The test build's on-screen windows, by the names its panels carry.
    static func windows() -> [Window] {
        guard let pid = testApp?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  let dict = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            let rect = CGRect(x: dict["X"] ?? 0, y: dict["Y"] ?? 0, width: dict["Width"] ?? 0, height: dict["Height"] ?? 0)
            return Window(name: info[kCGWindowName as String] as? String ?? "", bounds: rect)
        }
    }

    static func window(_ name: String) -> Window? { windows().first { $0.name == name } }

    /// An AX element in the test build's window named `name`.
    static func testElement(window name: String, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
        guard let pid = testApp?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        for window in (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        where (attr(window, kAXTitleAttribute) as? String) == name {
            if let hit = find(in: window, match) { return hit }
        }
        return nil
    }

    /// The number of underlines drawn, from the underline panel's window name ("BindAll Underlines: N").
    static func underlineCount() -> Int {
        guard let name = windows().first(where: { $0.name.hasPrefix("BindAll Underlines") })?.name,
              let n = Int(name.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") else { return 0 }
        return n
    }

    /// Every element under `root` with its role, title, description and value, for failure notes.
    static func dump(_ root: AXUIElement, depth: Int = 10, indent: String = "") -> String {
        let role = attr(root, kAXRoleAttribute) as? String ?? "?"
        let bits = [attr(root, kAXTitleAttribute) as? String, attr(root, kAXDescriptionAttribute) as? String,
                    (attr(root, kAXValueAttribute) as? String).map { "=" + $0.prefix(40) }]
            .compactMap { $0 }.filter { !$0.isEmpty }
        var out = "\(indent)\(role) \(bits.joined(separator: " | "))\n"
        guard depth > 0 else { return out }
        for child in (attr(root, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            out += dump(child, depth: depth - 1, indent: indent + "  ")
        }
        return out
    }

    /// The AX tree of the test build's window `name` (or all windows), for debugging a failed step.
    static func dumpTestWindows(_ name: String? = nil) -> String {
        guard let pid = testApp?.processIdentifier else { return "" }
        let app = AXUIElementCreateApplication(pid)
        return ((attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [])
            .filter { name == nil || (attr($0, kAXTitleAttribute) as? String) == name }
            .map { dump($0) }.joined(separator: "\n")
    }

    /// Finds by title or description (SwiftUI puts a button's name in one or the other).
    static func named(_ name: String) -> (AXUIElement) -> Bool {
        { (attr($0, kAXTitleAttribute) as? String) == name || (attr($0, kAXDescriptionAttribute) as? String) == name }
    }

    // MARK: Usage events

    static let usageDirectory = URL.applicationSupportDirectory.appending(path: "BindAll E2E/Usage")

    struct Event: Decodable {
        let feature: String
        let kind: String
        let reason: String?
        let detail: String?
        let time: Date
    }

    static func events(since: Date) -> [Event] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: usageDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.flatMap { file -> [Event] in
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").compactMap { try? decoder.decode(Event.self, from: Data($0.utf8)) }
        }.filter { $0.time >= since.addingTimeInterval(-1) }
    }

    static func hasEvent(_ feature: String, _ kind: String, since: Date, reason: String? = nil) -> Bool {
        events(since: since).contains { $0.feature == feature && $0.kind == kind && (reason == nil || $0.reason == reason) }
    }

    // MARK: Screen

    static func visibleScreenFrames() -> [CGRect] {
        let primary = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.map { s in
            CGRect(x: s.visibleFrame.minX, y: primary - s.visibleFrame.maxY, width: s.visibleFrame.width, height: s.visibleFrame.height)
        }
    }

    static func isOnScreen(_ rect: CGRect) -> Bool {
        visibleScreenFrames().contains { $0.insetBy(dx: -1, dy: -1).contains(rect) }
    }

    static func snapshot(_ rect: CGRect, to file: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let r = rect.insetBy(dx: -40, dy: -40)
        process.arguments = ["-x", "-R\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))", file.path]
        try? process.run()
        process.waitUntilExit()
    }
}
