import Foundation

/// Whether the star in a text field (nothing selected) shows: always by default, carrying the
/// number of issues Proofread found; or, when the user chose so, only while there are some.
enum FieldStarPolicy {
    /// Never in an empty field: a caret alone has nothing to act on.
    static func shows(onlyWithIssues: Bool, issues: Int, isEmpty: Bool) -> Bool {
        !isEmpty && (!onlyWithIssues || issues > 0)
    }
}
