import SwiftUI

/// The words added with "Add to dictionary" in the fixes popup, plus a field to add one by hand.
struct PersonalDictionarySection: View {
    @Environment(AppState.self) private var appState
    @State private var draft = ""

    var body: some View {
        Section {
            HStack {
                TextField("Add a word", text: $draft)
                    .textFieldStyle(.plain).darkField()
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(PersonalDictionary.normalize(draft).isEmpty)
            }
            if appState.settings.personalDictionary.isEmpty {
                Text("No words yet. Use the book icon in the fixes popup to add one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.settings.personalDictionary, id: \.self) { word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button("Remove \(word)", systemImage: "minus.circle") { remove(word) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            HelpHeader("Personal dictionary", "Words here are never underlined as misspellings, in any app. Case does not matter, and ё counts as е. Grammar and style checks still apply to them.")
        }
    }

    private func add() {
        appState.settings.personalDictionary = PersonalDictionary.adding(draft, to: appState.settings.personalDictionary)
        draft = ""
    }

    private func remove(_ word: String) {
        appState.settings.personalDictionary.removeAll { $0 == word }
    }
}
