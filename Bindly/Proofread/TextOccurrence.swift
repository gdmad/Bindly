import Foundation

enum TextOccurrence {
    /// The occurrence of `needle` in `text` whose start is nearest `estimate`: a word that appears
    /// twice in one text run must be measured where the issue is, not where it first occurs.
    static func nearest(_ needle: String, in text: NSString, to estimate: Int) -> NSRange? {
        guard !needle.isEmpty else { return nil }
        var best: NSRange?
        var search = NSRange(location: 0, length: text.length)
        while search.length > 0 {
            let found = text.range(of: needle, options: [.literal], range: search)
            guard found.location != NSNotFound else { break }
            if best == nil || abs(found.location - estimate) < abs(best!.location - estimate) { best = found }
            let next = found.location + max(1, found.length)
            search = NSRange(location: next, length: text.length - next)
        }
        return best
    }
}
