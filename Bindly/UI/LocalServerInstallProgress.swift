import SwiftUI

struct LocalServerInstallProgress: View {
    let fraction: Double
    let step: String
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: fraction) {
                Text(step)
            } currentValueLabel: {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            Button("Cancel", action: cancel)
        }
    }
}
