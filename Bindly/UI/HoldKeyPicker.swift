import SwiftUI

/// Chooses what is held for a voice action: one side's modifier key alone, or a custom shortcut.
struct HoldKeyPicker: View {
    let title: String
    /// The modifier this action defaults to (right Option or right Command).
    let modifierKey: PushToTalkKey
    @Binding var key: PushToTalkKey
    let others: [HotkeyConfig]

    @State private var usesModifier = true
    @State private var shortcut = HotkeyConfig(keyCode: 49, modifiers: HotkeyModifiers(command: false, control: true), repeatCount: 1)

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Picker(title, selection: $usesModifier) {
                    Text(modifierKey == .rightCommand ? "Right Command" : "Right Option").tag(true)
                    Text("Custom shortcut").tag(false)
                }
                .labelsHidden()
                .fixedSize()
                if !usesModifier {
                    ShortcutRecorder(config: $shortcut, others: others)
                }
            }
        }
        .onAppear {
            usesModifier = key == modifierKey
            if case .shortcut(let config) = key { shortcut = config }
        }
        .onChange(of: usesModifier) { _, modifier in
            Task { @MainActor in key = modifier ? modifierKey : .shortcut(shortcut) }
        }
        .onChange(of: shortcut) { _, config in
            guard !usesModifier else { return }
            Task { @MainActor in key = .shortcut(config) }
        }
    }
}
