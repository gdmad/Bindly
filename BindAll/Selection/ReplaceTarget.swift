import Foundation

/// Where a star's result goes now. The field may have changed while the result waited in a preview:
/// the same text is found again near where it was, and when it is gone there is no safe place.
enum ReplaceTarget {
    /// `range` was the subject's place in `original`; returns its place in `current`, or nil.
    static func range(_ range: NSRange, in original: String, now current: String) -> NSRange? {
        if current == original { return range }
        let subject = (original as NSString).substring(with: range)
        guard !subject.isEmpty, range.length < (original as NSString).length else { return nil }
        return TextOccurrence.nearest(subject, in: current as NSString, to: range.location)
    }
}
