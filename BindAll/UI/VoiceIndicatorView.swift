import SwiftUI

/// Push to Talk's note by the caret: the microphone while recording and what has been heard so far.
struct VoiceIndicatorView: View {
    let text: String
    let listening: Bool
    let level: VoiceLevel
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: PopupMetrics.inlineSpacing) {
            if listening {
                VoiceMicIcon(level: level, fontSize: PopupMetrics.secondaryFontSize(fontSize))
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
