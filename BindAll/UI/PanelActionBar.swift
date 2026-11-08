import SwiftUI

/// The button row of every BindAll window: secondary controls on the left, Close and then the main
/// action on the right, all at the same size.
struct PanelActionBar<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            leading
            Spacer(minLength: 12)
            trailing
        }
        .controlSize(.large)
    }
}
