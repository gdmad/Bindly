import SwiftUI

struct PopupOriginalSection: View {
    let original: String
    let language: String?
    let copied: Bool
    let copy: () -> Void
    let maxHeight: CGFloat
    let isManual: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Original")
                Button(copied ? "Copied" : "Copy original", systemImage: copied ? "checkmark" : "doc.on.doc",
                       action: copy)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Copy the original text")
                Spacer()
                if let language {
                    Text(language)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Its own share of the height, scrolling past it: as tall as the whole original, it
            // pushed the window off the screen.
            ScrollView {
                Text(original)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
            }
            .scrollBounceBehavior(.basedOnSize)
            .modifier(PanelScrollSizing(maxHeight: maxHeight, isManual: isManual))
        }
    }
}
