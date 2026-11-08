import SwiftUI

/// The local usage metrics: how many events are stored, where, and a way to clear them.
struct UsageDataRow: View {
    @State private var count: Int?
    @State private var confirmingClear = false

    var body: some View {
        LabeledContent {
            HStack {
                Button("Show in Finder", action: showInFinder)
                Button("Clear…", role: .destructive, action: askToClear)
                    .disabled(count == 0)
                    .confirmationDialog("Delete all usage data?", isPresented: $confirmingClear) {
                        Button("Delete", role: .destructive, action: clear)
                    } message: {
                        Text("Only the counts of how features were used are stored; this removes them.")
                    }
            }
            .controlSize(.small)
        } label: {
            HelpHeader(countText, "Bindly records which features you use, how often suggestions and fixes are accepted or dismissed, and why -- never the text you type. Stored on this Mac only (Application Support/Bindly/Usage), one file per month.")
        }
        .task { await reload() }
    }

    private var countText: String {
        guard let count else { return "Usage data" }
        return "Usage data: \(count.formatted()) events"
    }

    private func reload() async {
        count = await UsageLog.shared.events().count
    }

    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([UsageLog.defaultDirectory])
    }

    private func askToClear() {
        confirmingClear = true
    }

    private func clear() {
        Task {
            await UsageLog.shared.clear()
            await reload()
        }
    }
}
