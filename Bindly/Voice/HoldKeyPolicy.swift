import Foundation

/// Push to Talk's hold logic, free of timers and taps so it can be tested.
///
/// Recording starts only once the key has been held for `minHold` with nothing else pressed, so the
/// key keeps working as a modifier (right Option + a letter types a special character) and the
/// microphone never switches on for a quick tap. Releasing after that finishes; another key or Esc
/// while recording cancels.
struct HoldKeyPolicy {
    static let minHold: TimeInterval = 0.3

    enum Event: Equatable {
        case keyDown(at: TimeInterval)
        case keyUp(at: TimeInterval, shift: Bool)
        /// Checked by a timer while the key is down.
        case tick(at: TimeInterval)
        case otherKey
        case escape
    }

    enum Output: Equatable {
        case none
        case start
        /// `shift`: Shift was held at release (flips "translate before inserting" for this one).
        case finish(shift: Bool)
        case cancel
    }

    private enum Phase: Equatable { case idle, pressed(since: TimeInterval), usedAsModifier, recording }
    private var phase = Phase.idle

    var isRecording: Bool { phase == .recording }

    mutating func handle(_ event: Event) -> Output {
        switch (phase, event) {
        case (.idle, .keyDown(let time)):
            phase = .pressed(since: time)
        case (.pressed(let since), .tick(let time)) where time - since >= Self.minHold:
            phase = .recording
            return .start
        case (.pressed, .otherKey), (.pressed, .escape):
            phase = .usedAsModifier
        case (.recording, .keyUp(_, let shift)):
            phase = .idle
            return .finish(shift: shift)
        case (.recording, .otherKey), (.recording, .escape):
            phase = .idle
            return .cancel
        case (_, .keyUp):
            phase = .idle
        default:
            break
        }
        return .none
    }
}
