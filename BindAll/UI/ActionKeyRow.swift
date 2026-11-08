import SwiftUI

/// One action key: a summary line that expands into its editor.
struct ActionKeyRow: View {
    @Binding var key: ActionKey
    let delete: () -> Void

    @State private var isExpanded: Bool

    init(key: Binding<ActionKey>, startsExpanded: Bool, delete: @escaping () -> Void) {
        _key = key
        self.delete = delete
        _isExpanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("Name", text: deferredWrite($key.label), prompt: Text("What this key does"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .darkField()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Instruction").foregroundStyle(.secondary)
                    TextField("Instruction", text: deferredWrite($key.prompt),
                              prompt: Text("Describe the action for the AI…"), axis: .vertical)
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3...8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .darkField()
                }

                HStack {
                    HelpToggleRow("Show the result, do not replace the text", "For explanations and summaries: the result opens in a window and your text stays as it is.",
                                  isOn: $key.showOnly)
                        .controlSize(.small)
                    Spacer()
                    Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        } label: {
            // The whole summary line toggles the row, not just the chevron.
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Text(key.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let hotkey = key.hotkey {
                        Text(HotkeyFormatter.string(hotkey))
                            .foregroundStyle(.secondary)
                            .monospaced()
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func toggle() {
        isExpanded.toggle()
    }
}
