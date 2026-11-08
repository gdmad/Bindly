import Foundation

/// A self-hosted server is usually given as just its address ("http://192.168.1.5:8081"); the API
/// lives under /v2, and requests append "/check" to the base. A bare address gets /v2 added.
enum LanguageToolURL {
    static func normalized(_ base: String) -> String {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let components = URLComponents(string: trimmed), components.host != nil,
              components.path.isEmpty else { return trimmed }
        return trimmed + "/v2"
    }
}
