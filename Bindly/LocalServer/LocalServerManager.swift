import Foundation
import Observation

/// The single owner of the portable LanguageTool: install, update, run, stop, remove. The settings
/// UI reads `state` and calls the verbs; `AppState` calls `sync()` when the settings that decide
/// whether the server should be up change.
@MainActor @Observable
final class LocalServerManager {
    private(set) var state: LocalServerState = .notInstalled
    private(set) var isInstalled = false
    private(set) var manifest: LocalServerManifest?
    private(set) var isCheckingUpdates = false
    private(set) var updateError: String?
    /// Bytes on disk, for the "Remove" confirmation and the status row.
    private(set) var diskUsage: Int64 = 0
    /// Shown until dismissed, e.g. when the port had to change.
    var notice: String?

    /// Newer releases found by the last check; nil when up to date or never checked.
    var updates: LocalServerUpdates? { manifest?.available.flatMap { $0.any ? $0 : nil } }

    @ObservationIgnored let layout: LocalServerLayout
    @ObservationIgnored private let installer: LocalServerInstaller
    @ObservationIgnored weak var appState: AppState?
    @ObservationIgnored private var process: LocalServerProcess?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Bumped by every start/stop so a finishing task can tell it has been superseded.
    @ObservationIgnored private var generation = 0

    init(layout: LocalServerLayout = .standard) {
        self.layout = layout
        self.installer = LocalServerInstaller(layout: layout)
        refresh()
    }

    private var settings: Settings { appState?.settings ?? Settings() }

    // MARK: - Reading the disk

    /// Re-reads what is installed. Leaves a running, starting or installing server alone.
    func refresh() {
        switch state {
        case .installing, .starting, .running: return
        default: break
        }
        manifest = installer.readManifest()
        isInstalled = layout.isInstalled()
        if case .failed = state, isInstalled { return }
        state = isInstalled ? .stopped : .notInstalled
        updateDiskUsage()
    }

    private func updateDiskUsage() {
        let layout = self.layout
        Task {
            let size = await Task.detached { layout.diskUsage() }.value
            self.diskUsage = size
        }
    }

    // MARK: - Install / update / remove

    func install() {
        guard !isInstalled, !state.isBusy else { return }
        runInstall(.all, existing: nil)
    }

    func cancelInstall() {
        guard case .installing = state else { return }
        task?.cancel()
    }

    /// Replaces whichever pieces the last check found newer.
    func update() {
        guard isInstalled, !state.isBusy, let updates, let manifest else { return }
        var parts: LocalServerInstaller.Components = []
        if updates.jre { parts.insert(.jre) }
        if updates.languageTool { parts.insert(.languageTool) }
        runInstall(parts, existing: manifest)
    }

    private func runInstall(_ parts: LocalServerInstaller.Components, existing: LocalServerManifest?) {
        generation += 1
        let gen = generation
        let updating = existing != nil
        updateError = nil
        state = .installing(fraction: 0, step: updating ? "Preparing the update" : "Starting")
        let onProgress: LocalServerInstaller.Progress = { [weak self] fraction, step in
            Task { @MainActor in self?.installProgress(fraction, step) }
        }
        task = Task {
            await stopProcess()
            do {
                let result = try await installer.install(parts, existing: existing, progress: onProgress)
                guard gen == generation else { return }
                manifest = result
                isInstalled = true
                state = .stopped
                updateDiskUsage()
                sync()
            } catch {
                guard gen == generation else { return }
                let cancelled = error is CancellationError
                if updating {
                    // The swap rolls back, so the previous files are intact and the server can return.
                    state = .stopped
                    if !cancelled { updateError = error.localizedDescription }
                    sync()
                } else {
                    state = cancelled ? .notInstalled : .failed(error.localizedDescription)
                }
            }
        }
    }

    private func installProgress(_ fraction: Double, _ step: String) {
        guard case .installing(let current, _) = state else { return }
        state = .installing(fraction: max(current, fraction), step: step)
    }

    /// Stops the server if it is up and deletes the whole folder, then hands the settings back to
    /// the user's own URL (or the public server when there is none).
    func remove() {
        generation += 1
        let previous = task
        previous?.cancel()
        task = Task {
            await previous?.value
            await stopProcess()
            do {
                try installer.remove()
            } catch {
                refresh()
                state = .failed("Could not delete the folder: \(error.localizedDescription)")
                return
            }
            manifest = nil
            isInstalled = false
            diskUsage = 0
            notice = nil
            updateError = nil
            state = .notInstalled
            appState?.settings.localServerRemoved()
        }
    }

    // MARK: - Running

    /// Brings the server in line with the settings: up while the local target is selected, down
    /// otherwise, restarted when its port was changed.
    func sync() {
        let s = settings
        let wanted = s.usesLocalServer && isInstalled
        switch state {
        case .running(let port):
            if !wanted { stop() } else if port != s.localServerPort { stop(); start() }
        case .stopped, .failed:
            if wanted { start() }
        default:
            break
        }
    }

    func start() {
        guard isInstalled else { return }
        switch state {
        case .stopped, .failed: break
        default: return
        }
        generation += 1
        let gen = generation
        state = .starting
        task = Task { await launch(gen) }
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        let proc = process
        process = nil
        if isInstalled { state = .stopped }
        if let proc { Task.detached { proc.stop() } }
    }

    /// For `applicationWillTerminate`: blocks until the child is gone, so it is never left running.
    func stopForTermination() {
        task?.cancel()
        process?.stop()
        process = nil
    }

    private func launch(_ gen: Int) async {
        await LocalServerProcess.reapOrphan(layout: layout)
        guard gen == generation else { return }

        let preferred = settings.localServerPort
        guard let port = LocalServerPort.pick(preferred: preferred, isFree: LocalServerPort.isFree) else {
            state = .failed(LocalServerError.noFreePort.localizedDescription)
            return
        }
        if port != preferred {
            appState?.settings.localServerPort = port
            notice = "Port \(preferred) was busy, so the local server uses \(port). You can change it below."
        } else {
            notice = nil
        }

        let proc = LocalServerProcess(layout: layout)
        proc.onUnexpectedExit = { [weak self, weak proc] status in
            Task { @MainActor in
                guard let self, let proc else { return }
                self.processExited(proc, status: status)
            }
        }
        do {
            try proc.start(port: port)
            process = proc
            try await proc.waitUntilReady(port: port)
            guard gen == generation else { return }
            state = .running(port: port)
        } catch {
            if process === proc { process = nil }
            await Task.detached { proc.stop() }.value
            guard gen == generation else { return }
            state = error is CancellationError ? .stopped : .failed(error.localizedDescription)
        }
    }

    private func processExited(_ proc: LocalServerProcess, status: Int32) {
        guard process === proc else { return }
        process = nil
        switch state {
        case .running, .starting:
            let tail = proc.logTail()
            state = .failed("The server stopped unexpectedly (exit status \(status))." + (tail.isEmpty ? "" : " \(tail)"))
        default:
            break
        }
    }

    private func stopProcess() async {
        guard let proc = process else { return }
        process = nil
        await Task.detached { proc.stop() }.value
    }

    // MARK: - Updates

    /// One HEAD and one metadata request. Passive checks (`force == false`) run at most weekly and
    /// stay silent when offline; a manual one reports what went wrong.
    func checkForUpdates(force: Bool = false) {
        guard let current = manifest, isInstalled, !isCheckingUpdates else { return }
        if case .installing = state { return }
        guard force || current.isCheckDue() else { return }
        isCheckingUpdates = true
        updateError = nil
        Task {
            defer { isCheckingUpdates = false }
            do {
                let remote = try await installer.remoteVersions()
                guard var latest = manifest else { return }
                latest.lastUpdateCheck = Date()
                latest.available = latest.newer(than: remote)
                try? installer.write(latest)
                manifest = latest
            } catch {
                if force { updateError = "Could not check for updates: \(error.localizedDescription)" }
            }
        }
    }
}
