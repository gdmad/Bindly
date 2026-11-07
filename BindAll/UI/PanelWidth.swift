import AppKit

/// The width a result or preview window gets: wide enough for its longest line, within 380...560.
/// Given up front, so the height is measured at the width the text is drawn at -- left to SwiftUI's
/// ideal size, the text was measured as one line and the window came out too short for its own
/// buttons.
enum PanelWidth {
    static let range: ClosedRange<CGFloat> = 380...560

    static func fitting(_ texts: [String], font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)) -> CGFloat {
        let widest = texts
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        // A little slack: SwiftUI's text layout can need a point more than NSString measures.
        return min(range.upperBound, max(range.lowerBound, ceil(widest + 8)))
    }
}
