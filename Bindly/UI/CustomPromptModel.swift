import Foundation
import Observation

/// "Do this with my text": the instruction being typed, the last few, and what to do with the result.
@MainActor @Observable
final class CustomPromptModel {
    var prompt = ""
    var saveAsActionKey = false
    let recent: [String]
    /// "Selection" or "Whole text", so it is clear what the prompt will run on.
    let scope: String
    @ObservationIgnored let onRun: (_ prompt: String, _ showOnly: Bool, _ save: Bool) -> Void
    @ObservationIgnored let onClose: () -> Void

    init(recent: [String], scope: String, onRun: @escaping (String, Bool, Bool) -> Void, onClose: @escaping () -> Void) {
        self.recent = recent
        self.scope = scope
        self.onRun = onRun
        self.onClose = onClose
    }

    var canRun: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func run(showOnly: Bool) {
        guard canRun else { return }
        onRun(prompt.trimmingCharacters(in: .whitespacesAndNewlines), showOnly, saveAsActionKey)
    }

    func use(_ recentPrompt: String) {
        prompt = recentPrompt
    }
}
