import SwiftUI

/// The text: highlighted changes, or the result alone.
struct PreviewBody: View {
    let model: PreviewModel

    var body: some View {
        Group {
            switch model.mode {
            case .changes: Text(DiffText.attributed(model.parts))
            case .result: Text(model.result)
            }
        }
        .textSelection(.enabled)
    }
}
