import SwiftUI

/// The port is a setting. It commits on Return or when the field loses focus, so typing "8082"
/// does not restart the server at "808".
struct LocalServerPortRow: View {
    @EnvironmentObject var appState: AppState
    let server: LocalServerManager

    @State private var draft = LocalServerPort.defaultPort
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent("Port") {
            TextField("", value: $draft, format: .number.grouping(.never))
                .labelsHidden().textFieldStyle(.plain).darkField()
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .focused($focused)
                .onSubmit(commit)
        }
        .onAppear { draft = appState.settings.localServerPort }
        // The port can move on its own when it was busy.
        .onChange(of: appState.settings.localServerPort) { _, port in draft = port }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        if invalid {
            Text("Use a port between \(LocalServerPort.allowed.lowerBound) and \(LocalServerPort.allowed.upperBound).")
                .font(.caption).foregroundStyle(.red)
        }
    }

    private func commit() {
        invalid = !LocalServerPort.allowed.contains(draft)
        if invalid {
            draft = appState.settings.localServerPort
            return
        }
        guard draft != appState.settings.localServerPort else { return }
        appState.settings.localServerPort = draft
    }
}
