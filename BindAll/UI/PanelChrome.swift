import SwiftUI

/// The look shared by BindAll's result, preview, prompt and Quick Translate windows: the system
/// material (solid with Reduce Transparency, which the material honors itself), rounded, a hairline
/// border, even padding.
struct PanelChrome: ViewModifier {
    static let radius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(14)
            // Under everything: the margins and the gaps between controls move the window, while
            // buttons, fields and selectable text above it keep their own clicks.
            .background { WindowDragHandle() }
            .background(.regularMaterial, in: .rect(cornerRadius: Self.radius))
            .overlay {
                RoundedRectangle(cornerRadius: Self.radius)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .ignoresSafeArea()
    }
}

extension View {
    func panelChrome() -> some View {
        modifier(PanelChrome())
    }
}
