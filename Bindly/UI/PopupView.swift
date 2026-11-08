import SwiftUI

struct PopupView: View {
    @Bindable var model: PopupModel
    /// The text areas scroll beyond this together; below it the window is as tall as the text.
    let maxBodyHeight: CGFloat
    @Environment(PanelSizing.self) private var sizing: PanelSizing?

    private var isManual: Bool { sizing?.isManual ?? false }
    /// With the original shown the two share the height, so showing it never makes the window
    /// taller than the limit.
    private var showsOriginal: Bool { model.showOriginal && model.original != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopupHeader(title: model.title, languagePair: model.languagePair)
                .layoutPriority(1)

            ScrollView {
                Text(model.display)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .modifier(PanelScrollSizing(maxHeight: showsOriginal ? maxBodyHeight * 0.55 : maxBodyHeight, isManual: isManual))

            if model.showOriginal, let original = model.original {
                Divider()
                PopupOriginalSection(original: original, language: model.sourceLanguage,
                                     copied: model.copiedOriginal, copy: model.copyOriginal,
                                     maxHeight: maxBodyHeight * 0.45, isManual: isManual)
            }

            PanelActionBar {
                if model.original != nil {
                    Toggle("Show Original", isOn: $model.showOriginal)
                        .toggleStyle(.checkbox)
                }
            } trailing: {
                CloseButton(action: model.onClose)
                CopyButton(copied: model.copiedText, action: model.copyText)
                if let onReplace = model.onReplace {
                    Button(action: onReplace) {
                        Text("Replace").frame(minWidth: 56)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .layoutPriority(1)
        }
        .modifier(PanelRootSizing(width: model.width, isManual: isManual))
        .panelChrome()
        .overlay(alignment: .bottomTrailing) { ResizeGrip().padding(2) }
        .onExitCommand(perform: model.onClose)
    }
}
