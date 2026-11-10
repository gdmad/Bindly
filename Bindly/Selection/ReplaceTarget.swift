import Foundation

/// Where a star's result goes now. The field may have changed while the result waited in a preview:
/// the same text is found again near where it was, and when it is gone there is no safe place.
enum ReplaceTarget {
    /// The same text but for whitespace: web editors (Claude, Slack) report line and paragraph
    /// breaks their own way, so a re-read field can differ in nothing the user wrote.
    static func sameText(_ a: String, _ b: String) -> Bool {
        func squeezed(_ s: String) -> String { s.filter { !$0.isWhitespace && !$0.isNewline } }
        return squeezed(a) == squeezed(b)
    }

    /// Where the result of an action on the whole field goes: all of the field as it reads now, when
    /// that is still the text the action ran on (whitespace aside). Text typed since -- nil, so it is
    /// not overwritten.
    static func wholeField(original: String, now current: String) -> NSRange? {
        sameText(original, current) ? NSRange(location: 0, length: (current as NSString).length) : nil
    }

    /// `range` was the subject's place in `original`; returns its place in `current`, or nil.
    static func range(_ range: NSRange, in original: String, now current: String) -> NSRange? {
        if current == original { return range }
        let subject = (original as NSString).substring(with: range)
        guard !subject.isEmpty, range.length < (original as NSString).length else { return nil }
        return TextOccurrence.nearest(subject, in: current as NSString, to: range.location)
    }
}
