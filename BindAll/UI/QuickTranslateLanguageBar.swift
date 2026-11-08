import SwiftUI

struct QuickTranslateLanguageBar: View {
    @Binding var source: String
    @Binding var target: String
    let swap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("From", selection: $source) {
                Text("Auto").tag(AppLanguages.autoTag)
                ForEach(AppLanguages.list, id: \.code) { Text($0.name).tag($0.code) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button("Swap languages", systemImage: "arrow.left.arrow.right", action: swap)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .keyboardShortcut("/", modifiers: .command)
                .disabled(source == AppLanguages.autoTag)
                .help("Swap languages (Cmd+/)")

            Picker("To", selection: $target) {
                ForEach(AppLanguages.list, id: \.code) { Text($0.name).tag($0.code) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        // The window's top bar: its content covers the title bar, and moving by the background
        // does not reach through SwiftUI, so the space around the pickers drags it.
        .background { WindowDragHandle() }
    }
}
