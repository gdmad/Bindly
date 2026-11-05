import SwiftUI

/// What an action will do to the text, before it does it.
struct PreviewView: View {
    @Bindable var model: PreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PreviewHeader(title: model.title, mode: $model.mode)
            ScrollView {
                PreviewBody(model: model)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 10) {
                if !model.hasChanges {
                    Text("No changes").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                CloseButton(action: model.onClose)
                Button(action: model.copy) {
                    Text(model.copied ? "Copied" : "Copy").frame(minWidth: 56)
                }
                .controlSize(.large)
                Button(action: model.onApply) {
                    Text("Apply").frame(minWidth: 56)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.hasChanges)
            }
        }
        .padding(14)
        .frame(minWidth: 380, minHeight: 220)
        .onExitCommand(perform: model.onClose)
    }
}
