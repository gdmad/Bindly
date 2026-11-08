import Observation

/// Whether an action started from BindAll is running; the star animates while it is.
@MainActor
@Observable
final class StarActivity {
    var busy = false
    /// Issues found in the field: the field star's dot, tooltip and VoiceOver value; 0 shows none.
    var count = 0
    /// The most serious of them, which colors the dot.
    var worstIssue: IssueKind?
}
