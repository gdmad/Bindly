import SwiftUI

/// A compact language menu; `title` is for VoiceOver only.
struct LanguagePicker: View {
    let title: String
    @Binding var selection: String
    let includeAuto: Bool
    /// A choice ahead of the languages, such as "Same as Translation" (`tag` is stored as is).
    var leadingOption: (tag: String, title: String)?

    var body: some View {
        Picker(title, selection: $selection) {
            if includeAuto { Text("Auto Detect").tag(AppLanguages.autoTag) }
            if let leadingOption { Text(leadingOption.title).tag(leadingOption.tag) }
            ForEach(AppLanguages.list, id: \.code) { language in
                Text(language.name).tag(language.code)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}
