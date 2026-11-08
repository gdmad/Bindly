import Foundation

/// Whether the star in a text field (nothing selected) shows: always by default, carrying the
/// number of issues Proofread found; or, when the user chose so, only while there are some.
enum FieldStarPolicy {
    static func shows(onlyWithIssues: Bool, issues: Int) -> Bool {
        !onlyWithIssues || issues > 0
    }
}
