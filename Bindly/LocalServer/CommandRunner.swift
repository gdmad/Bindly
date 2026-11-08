import Foundation

/// Runs a system tool (`tar`, `ditto`, `xattr`, `ps`) and returns its output. The unpackers are the
/// system's own, so the app needs no archive library.
enum CommandRunner {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(decoding: data, as: UTF8.self)
                    if finished.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: LocalServerError.commandFailed(
                            "\((executable as NSString).lastPathComponent) exited with \(finished.terminationStatus)"
                            + (detail.isEmpty ? "" : ": \(detail)")))
                    }
                }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
