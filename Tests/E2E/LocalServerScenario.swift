import AppKit
import ApplicationServices
import Carbon.HIToolbox

// MARK: - The portable LanguageTool server, end to end
//
// Run only on request (E2E_ONLY=localServer, with E2E_LOCAL_SERVER=1): it downloads about 300 MB.
// Everything goes into the test build's own folder and is removed at the end.

private let serverRoot = URL.applicationSupportDirectory.appending(path: "Bindly E2E/LanguageTool", directoryHint: .isDirectory)

private func shell(_ path: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    try? p.run()
    p.waitUntilExit()
    return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

/// The java the test build started, if any.
private func serverPid() -> Int32? {
    shell("/usr/bin/pgrep", ["-f", "Bindly E2E/LanguageTool"]).split(separator: "\n").compactMap { Int32($0) }.first
}

private func testSettings() -> [String: Any] {
    guard let data = UserDefaults(suiteName: "com.evgeny.bindly.e2e")?.data(forKey: "Bindly.settings.v1"),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return json
}

private func serverPort() -> Int { testSettings()["localServerPort"] as? Int ?? 8081 }

/// The server answers a check on its own port.
private func serverAnswers(_ port: Int) -> Bool {
    shell("/usr/bin/curl", ["-s", "-m", "5", "-X", "POST", "-d", "text=Тут малако&language=ru-RU",
                             "http://127.0.0.1:\(port)/v2/check"]).contains("молоко")
}

private func settingsWindow() -> AXUIElement? {
    guard let pid = E2E.testApp?.processIdentifier else { return nil }
    let app = AXUIElementCreateApplication(pid)
    return ((E2E.attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []).first { (E2E.attr($0, kAXTitleAttribute) as? String) == "Bindly Settings" }
}

/// Opens Settings on the Proofread tab.
private func openProofreadSettings() -> AXUIElement? {
    if settingsWindow() == nil { _ = pressTrayItem("Settings…") }
    guard E2E.wait(4, { settingsWindow() != nil }), let window = settingsWindow(),
          let tab = E2E.find(in: window, depth: 14, { E2E.named("Proofread")($0) && (E2E.attr($0, kAXRoleAttribute) as? String) == "AXButton" }) else { return nil }
    E2E.press(tab)
    E2E.pause(1.0)
    return settingsWindow()
}

/// Presses the control named `name` in the Settings window (a button or a segment).
@discardableResult
private func pressInSettings(_ name: String) -> Bool {
    guard let window = settingsWindow(),
          let control = E2E.find(in: window, depth: 30, { element in
              let role = E2E.attr(element, kAXRoleAttribute) as? String
              return (role == "AXButton" || role == "AXRadioButton") && E2E.named(name)(element)
          }) else { return false }
    E2E.press(control)
    E2E.pause(0.8)
    return true
}

private func closeSettings() {
    if let window = settingsWindow(), let close = E2E.attr(window, kAXCloseButtonAttribute) { E2E.press(close as! AXUIElement) }
    E2E.pause(0.5)
}

func localServerScenario() {
    group = "Local server"
    let javaHomesBefore = shell("/bin/ls", ["/Library/Java/JavaVirtualMachines"])
    guard testSettings()["languageToolTarget"] as? String == "local" else {
        record("setup: run with E2E_LOCAL_SERVER=1", false); return
    }

    // 1. Install.
    guard openProofreadSettings() != nil, pressInSettings("Install local server…") else {
        record("setup: Install local server is on the Proofread tab", false); return
    }
    let started = Date()
    let running = E2E.wait(900, step: 5) { serverPid() != nil && serverAnswers(serverPort()) }
    record("Install downloads, unpacks and starts the server", running,
           String(format: "%.0f s", Date().timeIntervalSince(started)))
    guard running, let pid = serverPid() else { closeSettings(); return }
    let port = serverPort()
    let files = ["jre/Contents/Home/bin/java", "server/languagetool-server.jar", "install.json"]
        .allSatisfy { FileManager.default.fileExists(atPath: serverRoot.appending(path: $0).path) }
    record("everything is in the test build's own folder", files, serverRoot.path)
    let command = shell("/bin/ps", ["-o", "command=", "-p", "\(pid)"])
    record("the java running is the one in that folder", command.contains(serverRoot.path), String(command.prefix(160)))
    let listening = shell("/usr/sbin/lsof", ["-nP", "-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN"])
    record("it listens on this Mac only", listening.contains("127.0.0.1:\(port)") && !listening.contains("*:\(port)"),
           listening.split(separator: "\n").dropFirst().joined(separator: "; "))
    record("nothing went into the system's Java folder", shell("/bin/ls", ["/Library/Java/JavaVirtualMachines"]) == javaHomesBefore)
    record("no staging leftovers", !FileManager.default.fileExists(atPath: serverRoot.appending(path: ".staging").path))
    closeSettings()

    // 2. Checking goes through it.
    focusTextEdit()
    clearField()
    E2E.type("Вчера малако было свежее, а ощибка тут. ")
    record("text is checked by the local server", E2E.wait(20) { E2E.underlineCount() >= 2 }, "underlines \(E2E.underlineCount())")

    // 3. Custom URL stops it; Local server starts it again.
    guard openProofreadSettings() != nil else { return }
    pressInSettings("Custom URL")
    record("switching to Custom URL stops the server", E2E.wait(15) { serverPid() == nil })
    pressInSettings("Local server")
    record("switching back starts it again", E2E.wait(120, step: 2) { serverPid() != nil && serverAnswers(serverPort()) })

    // 4. A busy port: the server moves to the next free one.
    pressInSettings("Stop")
    _ = E2E.wait(15) { serverPid() == nil }
    let blocker = socket(AF_INET, SOCK_STREAM, 0)
    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(UInt16(port).bigEndian)
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(blocker, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    listen(blocker, 1)
    pressInSettings("Start")
    let moved = E2E.wait(120, step: 2) { serverPort() != port && serverAnswers(serverPort()) }
    record("a busy port moves the server to the next free one", moved, "port \(port) → \(serverPort())")
    close(blocker)

    // 5. Check for updates on a fresh install: nothing to do, files intact.
    pressInSettings("Check for updates")
    E2E.pause(8)
    record("an up-to-date install stays as it is",
           FileManager.default.fileExists(atPath: serverRoot.appending(path: "server/languagetool-server.jar").path) && serverPid() != nil)
    closeSettings()

    // 6. Quitting Bindly stops java; launching it starts java again.
    let bundle = E2E.testApp?.bundleURL
    _ = pressTrayItem("Quit Bindly")
    let quit = E2E.wait(15) { E2E.testApp == nil && serverPid() == nil }
    record("quitting Bindly stops the server", quit, "java \(serverPid().map(String.init) ?? "none")")
    if let bundle { NSWorkspace.shared.openApplication(at: bundle, configuration: .init()) }
    _ = E2E.wait(15) { E2E.testApp != nil }
    E2E.pause(3)
    record("launching Bindly starts it again", E2E.wait(120, step: 2) { serverPid() != nil && serverAnswers(serverPort()) })

    // 7. Remove: everything goes, the setting falls back.
    guard openProofreadSettings() != nil, pressInSettings("Remove…") else { record("Remove is offered", false); return }
    E2E.pause(0.8)
    let confirmed = pressInSettings("Remove")
    let gone = E2E.wait(30) { serverPid() == nil && !FileManager.default.fileExists(atPath: serverRoot.path) }
    record("Remove stops the server and deletes its folder", confirmed && gone,
           "confirmed \(confirmed), folder \(FileManager.default.fileExists(atPath: serverRoot.path) ? "still there" : "gone")")
    let s = testSettings()
    record("the setting falls back to the custom server", s["languageToolTarget"] as? String == "custom",
           "mode \(s["languageToolMode"] ?? "-"), target \(s["languageToolTarget"] ?? "-")")
    closeSettings()
    focusTextEdit()
}
