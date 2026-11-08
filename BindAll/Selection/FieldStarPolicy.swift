import Foundation

/// Whether the star in a text field (nothing selected) shows. It is the proofreading indicator:
/// by default only while issues are found, and never in a field too short to be checked (a search
/// box, an address, one word).
enum FieldStarPolicy {
    static func shows(always: Bool, textLength: Int, minLength: Int, issues: Int) -> Bool {
        guard textLength >= max(1, minLength) else { return false }
        return always || issues > 0
    }

    /// The count on the star: "9+" past nine.
    static func badge(_ issues: Int) -> String? {
        issues <= 0 ? nil : issues > 9 ? "9+" : "\(issues)"
    }
}
