import SwiftUI

struct MaskAISlopRuleRow: View {
    let rule: MaskAISlopRule
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.title)
                Text(rule.example)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }
}
