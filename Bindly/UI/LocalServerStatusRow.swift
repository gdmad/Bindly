import SwiftUI

/// What the server is doing, with the button that starts or stops it.
struct LocalServerStatusRow: View {
    let server: LocalServerManager
    /// Whether Local server is the selected target; the server only runs while it is.
    let isSelected: Bool

    var body: some View {
        LabeledContent("Status") {
            HStack(spacing: 8) {
                Label(statusText, systemImage: symbol)
                    .foregroundStyle(tint)
                    .labelStyle(.titleAndIcon)
                if server.state.isBusy {
                    ProgressView().controlSize(.small)
                } else if case .running = server.state {
                    Button("Stop", action: server.stop)
                } else {
                    Button("Start", action: server.start).disabled(!isSelected)
                }
            }
        }
        if case .failed(let message) = server.state {
            Text(message).font(.caption).foregroundStyle(.red)
        }
    }

    private var statusText: String {
        switch server.state {
        case .running(let port): return "Running on port \(port)"
        case .starting: return "Starting…"
        case .failed: return "Failed"
        default: return isSelected ? "Stopped" : "Not in use"
        }
    }

    private var symbol: String {
        switch server.state {
        case .running: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "circle"
        }
    }

    private var tint: Color {
        switch server.state {
        case .running: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
}
