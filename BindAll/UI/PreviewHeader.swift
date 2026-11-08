import SwiftUI

/// The preview's title and the Changes / Result switch; also the drag area of its panel.
struct PreviewHeader: View {
    let title: String
    @Binding var mode: PreviewModel.Mode

    var body: some View {
        HStack {
            // The drag area stops short of the switch, which must keep its clicks.
            HStack {
                Text(title).bold()
                Spacer()
            }
            .contentShape(.rect)
            .overlay { WindowDragHandle() }
            Picker("Show", selection: $mode) {
                ForEach(PreviewModel.Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .font(.callout)
    }
}
