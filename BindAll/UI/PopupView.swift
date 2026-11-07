import SwiftUI

struct PopupView: View {
    @Bindable var model: PopupModel
    /// The body scrolls beyond this; below it the window is as tall as the text.
    let maxBodyHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopupHeader(title: model.title, languagePair: model.languagePair)

            ScrollView {
                Text(model.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: maxBodyHeight)
            .fixedSize(horizontal: false, vertical: true)

            if model.showOriginal, let original = model.original {
                Divider()
                PopupOriginalSection(original: original, language: model.sourceLanguage,
                                     copied: model.copiedOriginal, copy: model.copyOriginal)
            }

            PanelActionBar {
                if model.original != nil {
                    Toggle("Show Original", isOn: $model.showOriginal)
                        .toggleStyle(.checkbox)
                }
            } trailing: {
                CloseButton(action: model.onClose)
                CopyButton(copied: model.copiedText, action: model.copyText)
            }
        }
        .frame(minWidth: 380, maxWidth: 560, alignment: .topLeading)
        .fixedSize()
        .panelChrome()
        .onExitCommand(perform: model.onClose)
    }
}
