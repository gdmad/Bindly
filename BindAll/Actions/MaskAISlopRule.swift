import Foundation

/// One thing Mask AI Slop can clean up; each can be switched on or off in Settings -> Actions.
enum MaskAISlopRule: String, CaseIterable, Codable, Identifiable {
    case dashes, quotes, ellipsis, spaces, emoji, decorativeEmoji, markdown, closers, stockPhrases

    var id: Self { self }

    /// On out of the box: the clean-ups Mask AI Slop always made. The newer ones change more of the
    /// text (Markdown structure, a closing line), so they are opt-in for results.
    static let defaults: Set<MaskAISlopRule> = [.dashes, .quotes, .ellipsis, .spaces, .emoji]

    /// What "Remove AI tells" uses: everything that changes text. Stock phrases are only listed.
    static let removeTells: Set<MaskAISlopRule> = Set(allCases).subtracting([.stockPhrases, .emoji])

    var title: String {
        switch self {
        case .dashes: "Long dashes"
        case .quotes: "Curly quotes and apostrophes"
        case .ellipsis: "Ellipsis character"
        case .spaces: "Non-breaking and thin spaces"
        case .emoji: "All emoji and symbols"
        case .decorativeEmoji: "Emoji at the end of lines"
        case .markdown: "Markdown leftovers"
        case .closers: "Sign-off phrases"
        case .stockPhrases: "Point out stock phrases"
        }
    }

    /// Before -> after, shown next to the switch.
    var example: String {
        switch self {
        case .dashes: "a — b → a - b"
        case .quotes: "“it’s” → \"it's\""
        case .ellipsis: "wait… → wait..."
        case .spaces: "10\u{00A0}km → 10 km"
        case .emoji: "done 🚀 now → done now"
        case .decorativeEmoji: "Shipped it! 🎉 → Shipped it!"
        case .markdown: "**bold**, ### Title → bold, Title"
        case .closers: "…\nLet me know if you have any questions! → …"
        case .stockPhrases: "delve, game-changer, важно отметить: listed in the preview, not changed"
        }
    }
}
