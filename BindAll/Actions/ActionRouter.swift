import Foundation

/// Builds an `AIEngine` for a given provider from the current settings + Keychain.
@MainActor
enum EngineFactory {
    /// `checksLanguage`: the action keeps the text's language (see `FallbackEngine`).
    static func make(kind: ProviderKind, appState: AppState, checksLanguage: Bool = false) -> AIEngine {
        switch kind {
        case .apple:
            guard let backup = appState.settings.appleFallbackProvider, backup != .apple else { return AppleFoundationEngine() }
            return FallbackEngine(primary: AppleFoundationEngine(), secondary: make(kind: backup, appState: appState),
                                  secondaryName: backup.displayName, checksLanguage: checksLanguage)
        case .deepseek, .openrouter, .openai, .ollama:
            let config = appState.settings.provider(kind)
            return OpenAICompatibleEngine(
                baseURL: config.effectiveBaseURL,
                apiKey: appState.apiKey(for: kind),
                model: config.model,
                requiresAPIKey: kind.requiresAPIKey,
                providerName: kind.displayName
            )
        }
    }

    /// Builds the LanguageTool client used by the "Correct" action from settings + Keychain.
    static func makeLanguageTool(appState: AppState) -> LanguageToolEngine {
        let s = appState.settings
        // The mode decides the real endpoint and whether credentials go on the wire.
        let conn = s.languageToolConnection(token: appState.languageToolToken())
        return LanguageToolEngine(
            baseURL: conn.baseURL,
            username: conn.username,
            apiKey: conn.apiKey,
            language: s.languageToolLanguage
        )
    }
}
