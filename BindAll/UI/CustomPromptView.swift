import SwiftUI

/// The field for a one-off instruction, with the recent ones under it.
struct CustomPromptView: View {
    @Bindable var model: CustomPromptModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Custom prompt · \(model.scope)", systemImage: "sparkle")
                .font(.callout.bold())
                .foregroundStyle(Color.brand)
                .overlay { WindowDragHandle().allowsHitTesting(false) }
            TextField("Prompt", text: $model.prompt, prompt: Text("What should happen to the text?"), axis: .vertical)
                .lineLimit(1...8)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(runAndReplace)
            if !model.recent.isEmpty {
                CustomPromptRecentList(prompts: model.recent, use: model.use)
            }
            PanelActionBar {
                Toggle("Save as action key", isOn: $model.saveAsActionKey)
                    .toggleStyle(.checkbox)
            } trailing: {
                CloseButton(action: model.onClose)
                Button(action: runAndShow) {
                    Text("Show").frame(minWidth: 56)
                }
                .disabled(!model.canRun)
                .help("Show the result without changing the text (⌥Return)")
                .keyboardShortcut(.return, modifiers: .option)
                Button(action: runAndReplace) {
                    Text("Run").frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canRun)
                .help("Run and preview the change (Return)")
            }
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .panelChrome()
        .onExitCommand(perform: model.onClose)
        .onAppear { focused = true }
    }

    private func runAndReplace() {
        model.run(showOnly: false)
    }

    private func runAndShow() {
        model.run(showOnly: true)
    }
}
