import Foundation

enum LocalServerError: LocalizedError {
    case badResponse(Int)
    case checksumMismatch
    case unexpectedArchive(String)
    case commandFailed(String)
    case notInstalled
    case noFreePort
    case exited(String)
    case notReady(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "The download failed (HTTP \(code))."
        case .checksumMismatch: return "The downloaded Java runtime did not match its published checksum."
        case .unexpectedArchive(let name): return "The \(name) archive did not have the expected contents."
        case .commandFailed(let detail): return "Unpacking failed: \(detail)"
        case .notInstalled: return "The local server is not installed."
        case .noFreePort: return "No free port was found near the configured one."
        case .exited(let tail): return tail.isEmpty ? "The server stopped right after it started." : "The server stopped: \(tail)"
        case .notReady(let tail): return tail.isEmpty ? "The server did not answer in time." : "The server did not answer in time: \(tail)"
        }
    }
}
