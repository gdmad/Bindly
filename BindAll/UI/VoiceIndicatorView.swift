import SwiftUI

/// Push to Talk's note by the caret: a recording dot and what has been heard so far.
struct VoiceIndicatorView: View {
    let text: String
    let listening: Bool
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: PopupMetrics.inlineSpacing) {
            if listening {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Working")
            }
            Text(text)
                .font(.system(size: PopupMetrics.secondaryFontSize(fontSize)))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: 360, alignment: .leading)
        }
        .popupChrome()
        .accessibilityElement(children: .combine)
    }
}
