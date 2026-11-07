import SwiftUI

/// What an action will do to the text, before it does it.
struct PreviewView: View {
    @Bindable var model: PreviewModel
    let maxBodyHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PreviewHeader(title: model.title, mode: $model.mode)
                .layoutPriority(1)
            ScrollView {
                PreviewBody(model: model)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: maxBodyHeight)
            .fixedSize(horizontal: false, vertical: true)
            if let note = model.note {
                Label(note, systemImage: "exclamationmark.bubble")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            PanelActionBar {
                Button(action: model.copy) {
                    Text(model.copied ? "Copied" : "Copy").frame(minWidth: 56)
                }
                if !model.hasChanges {
                    Text("No changes").font(.callout).foregroundStyle(.secondary)
                }
            } trailing: {
                CloseButton(action: model.onClose)
                Button(action: model.onApply) {
                    Text("Apply").frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.hasChanges)
            }
            .layoutPriority(1)
        }
        .frame(width: model.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .panelChrome()
        .onExitCommand(perform: model.onClose)
    }
}
