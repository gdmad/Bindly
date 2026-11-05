import SwiftUI

/// Which clean-ups Mask AI Slop makes, each with a before -> after example, and how far "Remove AI
/// tells" goes.
struct MaskAISlopSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Section {
            ForEach(MaskAISlopRule.allCases) { rule in
                MaskAISlopRuleRow(rule: rule, isOn: $appState.settings.maskAISlopRules.contains(rule.rawValue))
            }
            HelpToggleRow("Remove AI tells: also rewrite with AI", "The star menu's Remove AI tells always applies the rules above plus Markdown leftovers, emoji at line ends and sign-off lines. With this on it then asks the AI engine to rewrite stock phrases and filler too (slower, uses the engine).",
                          isOn: $appState.settings.removeTellsWithAI)
        } header: {
            HelpHeader("Mask AI Slop", "Applied to results of the actions when Mask AI Slop is on (General), and by Remove AI tells. Code in backticks and links are never changed.")
        }
    }
}
