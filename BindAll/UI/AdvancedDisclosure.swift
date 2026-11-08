import SwiftUI

/// Rarely changed options, folded away. Whether it is open is remembered per block.
struct AdvancedDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @AppStorage private var isExpanded: Bool

    init(_ title: String = "Advanced", id: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        _isExpanded = AppStorage(wrappedValue: false, "settings.disclosure.\(id)")
    }

    var body: some View {
        DisclosureGroup(title, isExpanded: $isExpanded) {
            content
        }
    }
}
