import Foundation

/// The settings sections, in tab-bar order. Every feature owns one tab, and that tab carries
/// everything about it -- starting with its own on/off switch.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, shortcuts, actions, translation, autocomplete, proofread, voice, providers

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .actions: "AI Actions"
        case .translation: "Translation"
        case .autocomplete: "Autocomplete"
        case .proofread: "Proofread"
        case .voice: "Voice"
        case .providers: "Providers"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "command"
        case .actions: "sparkles"
        case .translation: "globe"
        case .autocomplete: "text.append"
        case .proofread: "text.magnifyingglass"
        case .voice: "mic"
        case .providers: "cloud"
        }
    }
}
