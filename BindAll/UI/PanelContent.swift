import SwiftUI

/// A panel's root: its content at whole-point sizes (`IntegralSizeLayout`) with its `PanelSizing`.
struct PanelContent<Content: View>: View {
    let content: Content
    let sizing: PanelSizing

    var body: some View {
        IntegralSizeLayout { content }
            .environment(sizing)
    }
}
