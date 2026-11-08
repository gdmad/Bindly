import CoreGraphics
import Foundation

/// What a recognized screenshot holds, in reading order: paragraphs, lists and tables. Built from
/// Vision's document observation (`OCRService`), turned into the text that is translated and shown.
enum DocumentLayout {
    enum Content: Equatable {
        case paragraph(String)
        case list([String])
        case table([[String]])
    }

    struct Block: Equatable {
        let content: Content
        /// Normalized, Vision's: origin at the bottom left, so a larger `maxY` is higher up.
        let box: CGRect
    }

    /// Top to bottom, a blank line between blocks; list items as "• item", table rows one per line
    /// with Tab between the cells. A paragraph lying inside a list or a table is that same text
    /// again, as Vision also reports it among the paragraphs, and is left out.
    static func render(_ blocks: [Block]) -> String {
        let containers = blocks.filter { if case .paragraph = $0.content { false } else { true } }.map(\.box)
        let kept = blocks.filter { block in
            guard case .paragraph = block.content else { return true }
            return !containers.contains { $0.insetBy(dx: -0.01, dy: -0.01).contains(block.box) }
        }
        return kept
            .sorted { $0.box.maxY > $1.box.maxY }
            .map { block in
                switch block.content {
                case .paragraph(let text): text
                case .list(let items): items.map { "• " + strippedMarker($0) }.joined(separator: "\n")
                case .table(let rows): rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
                }
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    /// The item's own marker ("•", "-", "1.") as read off the screen, so it is not doubled.
    static func strippedMarker(_ item: String) -> String {
        let trimmed = item.trimmingCharacters(in: .whitespaces)
        for marker in ["•", "◦", "▪", "-", "–", "—", "*"] where trimmed.hasPrefix(marker) {
            return trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        }
        if let dot = trimmed.firstIndex(where: { $0 == "." || $0 == ")" }),
           trimmed.distance(from: trimmed.startIndex, to: dot) <= 3,
           trimmed[..<dot].allSatisfy(\.isNumber), !trimmed[..<dot].isEmpty {
            return trimmed[trimmed.index(after: dot)...].trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }
}
