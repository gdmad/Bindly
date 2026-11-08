import SwiftUI

/// The microphone, in the icon's violet, while Push to Talk records; it swells with the voice, so a
/// silent input shows at once. Still with Reduce Motion.
struct VoiceMicIcon: View {
    let level: VoiceLevel
    let fontSize: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let value = reduceMotion ? 1 : level.value
        Image(systemName: "mic.fill")
            .font(.system(size: fontSize))
            .foregroundStyle(Color.brand)
            .scaleEffect(1 + 0.3 * value)
            .opacity(0.75 + 0.25 * value)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: value)
            .frame(width: fontSize * 1.4, height: fontSize * 1.4)
            .accessibilityLabel("Recording")
    }
}
