import Observation

/// Whether an action started from BindAll is running; the star animates while it is.
@MainActor
@Observable
final class StarActivity {
    var busy = false
    /// Issues found in the field, shown on the field star; 0 shows none.
    var count = 0
}
