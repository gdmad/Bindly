import SwiftUI
import AppKit

/// Install, run, update and remove the portable LanguageTool. Shown in Self-hosted mode; the
/// state itself lives in `LocalServerManager`.
struct LocalServerSection: View {
    @Environment(AppState.self) private var appState
    @State private var confirmingRemoval = false

    private var server: LocalServerManager { appState.localServer }

    var body: some View {
        Section {
            switch server.state {
            case .installing(let fraction, let step):
                LocalServerInstallProgress(fraction: fraction, step: step, cancel: server.cancelInstall)
            default:
                if server.isInstalled {
                    LocalServerStatusRow(server: server, isSelected: appState.settings.languageToolTarget == .local)
                    LocalServerPortRow(server: server)
                    LocalServerUpdateRow(server: server)
                    manageRow
                } else {
                    installRow
                }
            }
            if let notice = server.notice, server.isInstalled {
                Text(notice).font(.caption).foregroundStyle(.orange)
            }
        } header: {
            HelpHeader("Local server", "A LanguageTool server that Bindly installs and runs for you, so text never leaves this Mac.\n\nInstall downloads a Java runtime (Temurin 21, ~48 MB) and LanguageTool (~250 MB); about 540 MB on disk once unpacked. Both go into one folder, ~/Library/Application Support/Bindly/LanguageTool. Nothing is installed into the system and Java is not shared with other apps.\n\nThe server listens on this Mac only (127.0.0.1) and starts when Bindly does, while Local server is selected. The Java runtime is verified against its published checksum; LanguageTool publishes none, so its archive is only checked to be intact.\n\nUpdates are never downloaded on their own: Bindly checks about once a week and offers them. Remove stops the server and deletes the whole folder. Dragging Bindly to the Trash does not delete it, so use Remove first.\n\nGoogle Docs draws its text on a canvas that no app can read, so Bindly cannot check it. The LanguageTool browser extension can: in its Advanced settings choose a local or other server and enter http://127.0.0.1:<port>/v2.")
        }
        .onAppear {
            server.refresh()
            server.checkForUpdates()
        }
        .confirmationDialog("Remove the local server?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive, action: server.remove)
        } message: {
            Text("This stops the server and deletes the Java runtime and LanguageTool (\(sizeText)). You can install them again later.")
        }
    }

    private var installRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Install local server…", action: server.install)
            if case .failed(let message) = server.state {
                Text(message).font(.caption).foregroundStyle(.red)
            } else {
                Text("Downloads about 300 MB. Nothing is installed into the system.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var manageRow: some View {
        HStack {
            Button("Show in Finder", action: revealInFinder)
            Spacer()
            Text(sizeText).font(.caption).foregroundStyle(.secondary)
            Button("Remove…", role: .destructive) { confirmingRemoval = true }
                .disabled(server.state.isBusy)
        }
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: server.diskUsage, countStyle: .file)
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([server.layout.root])
    }
}
