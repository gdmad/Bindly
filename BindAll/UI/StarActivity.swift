import Observation

/// Whether an action started from BindAll is running; the star animates while it is.
@MainActor
@Observable
final class StarActivity {
    var busy = false
}
