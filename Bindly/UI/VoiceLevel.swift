import Observation

/// The microphone's current level (0...1) for the recording indicator; updated without rebuilding
/// the note, so only the icon redraws.
@MainActor
@Observable
final class VoiceLevel {
    var value: Double = 0
}
