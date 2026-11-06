import Foundation

/// Every issue's first fix applied to the text at once, for "Fix all".
enum FixAll {
    struct Outcome: Equatable {
        let text: String
        /// Issues that were actually fixed (an issue with no fix, or one overlapping another, is left).
        let fixed: Int
    }

    /// The issues that "Fix all" would change.
    static func fixable(_ issues: [TextIssue]) -> [TextIssue] {
        issues.filter { !$0.replacements.isEmpty }
    }

    /// Applies the first replacement of each issue. Issues are relocated in `text` first (the field
    /// may have changed since the check); ones that cannot be found or overlap an earlier one are
    /// skipped. Works from the end so earlier ranges stay valid.
    static func apply(_ issues: [TextIssue], to text: String) -> Outcome {
        var placed: [(NSRange, String)] = []
        for issue in fixable(issues) {
            guard let range = IssueMerger.relocate(issue, in: text), let replacement = issue.replacements.first,
                  !placed.contains(where: { NSIntersectionRange($0.0, range).length > 0 || $0.0.location == range.location })
            else { continue }
            placed.append((range, replacement))
        }
        let result = NSMutableString(string: text)
        for (range, replacement) in placed.sorted(by: { $0.0.location > $1.0.location }) {
            result.replaceCharacters(in: range, with: replacement)
        }
        return Outcome(text: result as String, fixed: placed.count)
    }
}
