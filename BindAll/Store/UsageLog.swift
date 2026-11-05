import AppKit
import Foundation

/// What BindAll feature an event is about.
enum UsageFeature: String, Codable, CaseIterable {
    case autocomplete, proofread, fix, actionKey, translate, ocr, quickTranslate, translationPopup,
         star, preview, customPrompt, spelling
}

/// What happened. "Shown" without a following "accepted"/"applied" is the interesting part: it is
/// how unused features show up, together with the `reason` they were dismissed for.
enum UsageEventKind: String, Codable, CaseIterable {
    case shown, accepted, applied, skipped, dismissed, failed
}

/// One usage event. Never carries user text: only the feature, the kind, the app it happened in,
/// timings and short fixed tokens (`reason`, `detail`) chosen by the code, not by the user.
struct UsageEvent: Codable, Equatable {
    var time: Date
    var feature: UsageFeature
    var kind: UsageEventKind
    /// Bundle identifier of the frontmost app.
    var app: String?
    /// How long the operation took, where that means something (engine round trips).
    var ms: Int?
    /// Why it was dismissed or failed: "esc", "typedOn", "navigation", "stale", "error"...
    var reason: String?
    /// Fixed extra context: "tab", "return", "click", "index:2", "source:hotkey", an action key's key.
    var detail: String?
}

/// Local, append-only usage metrics, so later we can see which features are used, which are not,
/// and why they get dismissed. Written as JSON lines to one file per month in Application Support;
/// nothing leaves the Mac.
actor UsageLog {
    static let shared = UsageLog()

    let directory: URL

    init(directory: URL = UsageLog.defaultDirectory) {
        self.directory = directory
    }

    nonisolated static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "BindAll/Usage", directoryHint: .isDirectory)
    }

    /// Fire-and-forget: callers on the main thread never wait for the disk.
    nonisolated static func record(_ feature: UsageFeature, _ kind: UsageEventKind, reason: String? = nil,
                                   detail: String? = nil, ms: Int? = nil) {
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let event = UsageEvent(time: .now, feature: feature, kind: kind, app: app, ms: ms,
                               reason: reason, detail: detail)
        Task { await shared.append(event) }
    }

    /// Milliseconds since `start`, for `ms:`.
    nonisolated static func elapsed(since start: ContinuousClock.Instant) -> Int {
        let duration = ContinuousClock.now - start
        return Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    func append(_ event: UsageEvent) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard var line = try? encoder.encode(event) else { return }
        line.append(0x0A)
        let file = fileURL(for: event.time)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: file)
            }
        } catch {
            // Metrics must never get in the way; a lost event is fine.
        }
    }

    /// One file per month keeps any single file small and makes "forget the old data" a delete.
    func fileURL(for date: Date) -> URL {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: date)
        let month = parts.month ?? 0
        return directory.appending(path: "usage-\(parts.year ?? 0)-\(month < 10 ? "0" : "")\(month).jsonl")
    }

    /// Every stored event, oldest first.
    func events() -> [UsageEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return files.flatMap { file -> [UsageEvent] in
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").compactMap { try? decoder.decode(UsageEvent.self, from: Data($0.utf8)) }
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
