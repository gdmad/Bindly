import Foundation

/// Model answers come with Markdown (bold, italics, headings); a result window shows them styled
/// instead of with the asterisks, and Copy gives the text without them.
enum ResultMarkdown {
    static func render(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: headingsAsBold(text), options: options)) ?? AttributedString(text)
    }

    static func plain(_ text: String) -> String {
        String(render(text).characters)
    }

    /// Inline-only parsing leaves "## Title" as it is; a bold line reads the same in a small window.
    private static func headingsAsBold(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            let hashes = line.prefix { $0 == "#" }.count
            guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return line }
            let title = line.dropFirst(hashes + 1).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? line : "**\(title)**"
        }.joined(separator: "\n")
    }
}
