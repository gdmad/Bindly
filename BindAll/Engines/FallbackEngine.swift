import Foundation

/// The Apple model first, a cloud provider when it cannot: it refused or failed, or -- for the
/// built-in actions that keep the text's language -- answered in another one. Opt-in, since the
/// text then leaves the Mac. Esc is never a reason to try again elsewhere.
struct FallbackEngine: AIEngine {
    let primary: AIEngine
    let secondary: AIEngine
    let secondaryName: String
    /// Fix, Explain, Summarize, Remove AI tells: the answer must be in the text's language. A custom
    /// prompt may well ask for a translation, so it is not checked.
    let checksLanguage: Bool

    func process(text: String, instruction: String) async throws -> String {
        try await answer(text: text, instruction: instruction).text
    }

    func answer(text: String, instruction: String) async throws -> EngineAnswer {
        let first: String
        do {
            first = try await primary.process(text: text, instruction: instruction)
        } catch {
            if Task.isCancelled || error is CancellationError { throw error }
            return try await fallback(text, instruction)
        }
        if checksLanguage, LanguageMatch.differs(input: text, output: first) {
            return try await fallback(text, instruction)
        }
        return EngineAnswer(text: first, answeredBy: nil)
    }

    private func fallback(_ text: String, _ instruction: String) async throws -> EngineAnswer {
        try Task.checkCancellation()
        return EngineAnswer(text: try await secondary.process(text: text, instruction: instruction), answeredBy: secondaryName)
    }

    func testConnection() async throws -> String { try await primary.testConnection() }
}

/// A result and, when a fallback gave it, who did.
struct EngineAnswer: Equatable {
    let text: String
    let answeredBy: String?
}

extension AIEngine {
    func answer(text: String, instruction: String) async throws -> EngineAnswer {
        EngineAnswer(text: try await process(text: text, instruction: instruction), answeredBy: nil)
    }
}
