import Foundation

/// The running `java ... HTTPServer` child. Only one exists at a time.
final class LocalServerProcess: @unchecked Sendable {
    private let layout: LocalServerLayout
    private let process = Process()
    private let lock = NSLock()
    private var stopRequested = false

    /// Called on an arbitrary queue when the process ends without `stop()` having been asked for.
    var onUnexpectedExit: (@Sendable (_ status: Int32) -> Void)?

    init(layout: LocalServerLayout) { self.layout = layout }

    var isRunning: Bool { process.isRunning }

    /// Starts the server on `port`, bound to the loopback interface only (no `--public`).
    func start(port: Int) throws {
        let fm = FileManager.default
        fm.createFile(atPath: layout.logFile.path, contents: nil)
        let log = try FileHandle(forWritingTo: layout.logFile)

        process.executableURL = layout.javaExecutable
        process.currentDirectoryURL = layout.serverDir
        process.arguments = ["-Xmx768m", "-cp", "languagetool-server.jar",
                             "org.languagetool.server.HTTPServer", "--port", String(port)]
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { [weak self] finished in
            try? log.close()
            guard let self else { return }
            // A restart may already have written its own PID: remove the file only if it is still ours.
            let recorded = try? String(contentsOf: self.layout.pidFile, encoding: .utf8)
            if recorded == String(finished.processIdentifier) { try? FileManager.default.removeItem(at: self.layout.pidFile) }
            self.lock.lock()
            let requested = self.stopRequested
            self.lock.unlock()
            if !requested { self.onUnexpectedExit?(finished.terminationStatus) }
        }
        try process.run()
        try? String(process.processIdentifier).write(to: layout.pidFile, atomically: true, encoding: .utf8)
    }

    /// SIGTERM, then SIGKILL if the JVM has not gone within two seconds. Blocking, so it also works
    /// from `applicationWillTerminate`.
    func stop() {
        lock.lock(); stopRequested = true; lock.unlock()
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    /// Polls `/v2/languages` until the server answers. Gives up when the process is gone or
    /// `timeout` passes.
    func waitUntilReady(port: Int, timeout: TimeInterval = 40) async throws {
        let url = URL(string: "http://127.0.0.1:\(port)/v2/languages")!
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if !process.isRunning { throw LocalServerError.exited(logTail()) }
            var request = URLRequest(url: url, timeoutInterval: 2)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            if let (_, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 { return }
            try await Task.sleep(for: .milliseconds(400))
        }
        throw LocalServerError.notReady(logTail())
    }

    /// The last meaningful line of the server log, for error messages.
    func logTail() -> String {
        guard let text = try? String(contentsOf: layout.logFile, encoding: .utf8) else { return "" }
        return text.split(separator: "\n").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            .map(String.init) ?? ""
    }

    /// A server left behind by a crashed run would hold the port and the files. Only a process that
    /// both matches the recorded PID and runs from inside our folder is touched.
    static func reapOrphan(layout: LocalServerLayout) async {
        guard let text = try? String(contentsOf: layout.pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else { return }
        defer { try? FileManager.default.removeItem(at: layout.pidFile) }
        guard let command = try? await CommandRunner.run("/bin/ps", ["-p", String(pid), "-o", "command="]),
              command.contains(layout.root.path) else { return }
        kill(pid, SIGTERM)
        for _ in 0..<40 where kill(pid, 0) == 0 { try? await Task.sleep(for: .milliseconds(50)) }
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }
}
