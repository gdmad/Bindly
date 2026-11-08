import Foundation

enum LocalServerState: Equatable {
    case notInstalled
    /// `fraction` is 0...1 across the whole install; `step` names what is happening.
    case installing(fraction: Double, step: String)
    case stopped
    case starting
    case running(port: Int)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .installing, .starting: return true
        default: return false
        }
    }
}
