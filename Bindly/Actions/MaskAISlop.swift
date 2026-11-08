import Foundation

/// Normalizes "AI slop" so generated text looks like a human typed it. Which clean-ups run is a set
/// of `MaskAISlopRule`s. Code in backticks and URLs are never touched.
enum MaskAISlop {
    /// `keeping`: the text the result was made from. A character the user typed there themselves
    /// (their «», —, an emoji) is theirs, not slop, and stays.
    static func apply(to input: String, rules: Set<MaskAISlopRule> = MaskAISlopRule.defaults, keeping original: String? = nil) -> String {
        let kept = Set((original ?? "").unicodeScalars.filter { !$0.isASCII })
        var out = ""
        for segment in segments(of: input) {
            out += segment.isProtected ? segment.text : clean(segment.text, rules: rules, keeping: kept)
        }
        if rules.contains(.closers) { out = removeClosers(out) }
        return out
    }

    // MARK: - Stock phrases

    /// Typical generated-text phrases, English and Russian. Matched case-insensitively.
    static let stockPhrases: [String] = [
        "delve", "delving", "truly", "game-changer", "game changer", "tapestry", "testament to",
        "in today's fast-paced world", "it's worth noting", "it is important to note", "seamlessly",
        "leverage", "unlock the potential", "navigate the complexities", "a rich tapestry",
        "great question", "i hope this helps", "rest assured",
        "важно отметить", "давайте разберёмся", "в современном мире", "стоит отметить",
        "не секрет, что", "в заключение", "таким образом, можно сказать",
    ]

    /// The stock phrases present in `text`, in the order of the list, each once.
    static func stockPhrases(in text: String) -> [String] {
        let lower = text.lowercased()
        return stockPhrases.filter { lower.contains($0) }
    }

    // MARK: - Protected spans

    struct Segment: Equatable {
        let text: String
        let isProtected: Bool
    }

    /// Splits off code (```fenced```, `inline`) and URLs, which must come through unchanged.
    static func segments(of text: String) -> [Segment] {
        let pattern = #"```[\s\S]*?```|`[^`\n]+`|https?://\S+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [Segment(text: text, isProtected: false)] }
        let ns = text as NSString
        var out: [Segment] = []
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                out.append(Segment(text: ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)),
                                   isProtected: false))
            }
            out.append(Segment(text: ns.substring(with: match.range), isProtected: true))
            cursor = NSMaxRange(match.range)
        }
        if cursor < ns.length {
            out.append(Segment(text: ns.substring(from: cursor), isProtected: false))
        }
        return out
    }

    // MARK: - Rules

    private static func clean(_ input: String, rules: Set<MaskAISlopRule>, keeping kept: Set<Unicode.Scalar>) -> String {
        var text = input
        if rules.contains(.markdown) { text = removeMarkdown(text) }
        if rules.contains(.decorativeEmoji), !rules.contains(.emoji) { text = removeTrailingEmoji(text) }

        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(text.unicodeScalars.count)
        // Set when a scalar was stripped right after a space: the next space is swallowed so a
        // removal never leaves a doubled space ("hi 😀 there" -> "hi there"), while pre-existing
        // runs of spaces (indentation, column alignment) survive untouched.
        var strippedAfterSpace = false

        for scalar in text.unicodeScalars {
            if kept.contains(scalar) {
                scalars.append(scalar)
                strippedAfterSpace = false
                continue
            }
            if rules.contains(.emoji), shouldStrip(scalar) {
                if scalars.last == " " { strippedAfterSpace = true }
                continue
            }
            switch scalar {
            case "\u{2014}", "\u{2013}", "\u{2012}", "\u{2015}", "\u{2212}":
                rules.contains(.dashes) ? scalars.append("-") : scalars.append(scalar)
            case "\u{201C}", "\u{201D}", "\u{201E}", "\u{201F}", "\u{00AB}", "\u{00BB}", "\u{2033}":
                rules.contains(.quotes) ? scalars.append("\"") : scalars.append(scalar)
            case "\u{2018}", "\u{2019}", "\u{201A}", "\u{201B}", "\u{2032}":
                rules.contains(.quotes) ? scalars.append("'") : scalars.append(scalar)
            case "\u{2026}":
                rules.contains(.ellipsis) ? scalars.append(contentsOf: "...".unicodeScalars) : scalars.append(scalar)
            case " ", "\u{00A0}", "\u{2009}", "\u{202F}", "\u{2007}":
                if strippedAfterSpace {
                    strippedAfterSpace = false
                    continue
                }
                scalars.append(scalar == " " || rules.contains(.spaces) ? " " : scalar)
            default:
                scalars.append(scalar)
            }
            strippedAfterSpace = false
        }
        return String(scalars)
    }

    /// `**bold**`, `__bold__`, `*em*` markers and `#`-headings: what generated text leaves behind
    /// when pasted into a chat that does not render Markdown.
    static func removeMarkdown(_ text: String) -> String {
        var out = text
        let replacements: [(String, String)] = [
            (#"\*\*(.+?)\*\*"#, "$1"),
            (#"__(.+?)__"#, "$1"),
            (#"(?m)^[ \t]*#{1,6}[ \t]+"#, ""),
        ]
        for (pattern, template) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            out = regex.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length),
                                                 withTemplate: template)
        }
        return out
    }

    /// Emoji right before the end of a line ("Shipped it! 🎉"), not those inside a sentence.
    static func removeTrailingEmoji(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var scalars = Array(line.unicodeScalars)
            var removed = false
            while let last = scalars.last {
                if shouldStrip(last) {
                    scalars.removeLast()
                    removed = true
                } else if last == " ", removed || (scalars.dropLast().last.map(shouldStrip) ?? false) {
                    scalars.removeLast()
                } else {
                    break
                }
            }
            return removed ? String(String.UnicodeScalarView(scalars)) : String(line)
        }.joined(separator: "\n")
    }

    /// A final line that is only a sign-off ("Let me know if you have any questions!").
    static func removeClosers(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty, lines.count > 1 {
            lines.removeLast()
        }
        guard let last = lines.last else { return text }
        let lower = last.lowercased().trimmingCharacters(in: .whitespaces)
        guard closers.contains(where: { lower.hasPrefix($0) }) else { return text }
        lines.removeLast()
        while let tail = lines.last, tail.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    private static let closers = [
        "let me know if you have any", "i hope this helps", "hope this helps", "feel free to reach out",
        "feel free to ask", "happy to help", "если остались вопросы", "надеюсь, это поможет",
        "обращайтесь, если", "дайте знать, если",
    ]

    private static func shouldStrip(_ scalar: Unicode.Scalar) -> Bool {
        // Keep tab/newline/carriage return.
        if scalar == "\t" || scalar == "\n" || scalar == "\r" { return false }

        let props = scalar.properties
        if props.isEmoji && scalar.value > 0x238C { return true } // emoji (skip basic ASCII overlap)
        if props.isEmojiPresentation || props.isEmojiModifier || props.isEmojiModifierBase { return true }

        switch props.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned,
             .lineSeparator, .paragraphSeparator,
             .nonspacingMark, .enclosingMark,
             .otherSymbol:
            return true
        default:
            // Variation selectors / zero-width joiners.
            if (0xFE00...0xFE0F).contains(scalar.value) { return true }
            if scalar.value == 0x200D || scalar.value == 0x200B || scalar.value == 0x200C { return true }
            return false
        }
    }
}
