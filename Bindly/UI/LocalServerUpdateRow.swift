import SwiftUI

/// Update availability. Nothing is downloaded until the user asks.
struct LocalServerUpdateRow: View {
    let server: LocalServerManager

    var body: some View {
        HStack {
            if let updates = server.updates {
                Text(summary(updates)).font(.callout)
                Spacer()
                Button("Update", action: server.update).disabled(server.state.isBusy)
            } else {
                Text(versionText).font(.callout).foregroundStyle(.secondary)
                Spacer()
                if server.isCheckingUpdates { ProgressView().controlSize(.small) }
                Button("Check for updates") { server.checkForUpdates(force: true) }
                    .disabled(server.isCheckingUpdates || server.state.isBusy)
            }
        }
        if let error = server.updateError {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    private var versionText: String {
        guard let manifest = server.manifest else { return "" }
        return "LanguageTool \(manifest.languageToolVersion) · up to date"
    }

    private func summary(_ updates: LocalServerUpdates) -> String {
        switch (updates.jre, updates.languageTool) {
        case (true, true): return "Updates available: LanguageTool and Java"
        case (false, true): return "Update available: LanguageTool"
        default: return "Update available: Java runtime"
        }
    }
}
