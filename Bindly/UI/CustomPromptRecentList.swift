import SwiftUI

/// The last few custom prompts; a click puts one back into the field.
struct CustomPromptRecentList: View {
    let prompts: [String]
    let use: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent").font(.caption).foregroundStyle(.secondary)
            ForEach(prompts, id: \.self) { prompt in
                Button(prompt) { use(prompt) }
                    .buttonStyle(.plain)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
            }
        }
    }
}
