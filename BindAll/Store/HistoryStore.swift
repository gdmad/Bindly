import Foundation
import Observation

/// One successful operation kept in history. API keys are never part of an entry.
struct HistoryEntry: Identifiable, Equatable {
    enum Kind: String, Codable {
        case action
        case translate
        case ocr
        case quick
        case voice

        var label: String {
            switch self {
            case .action: return "Action"
            case .translate: return "Translate"
            case .ocr: return "OCR"
            case .quick: return "Quick"
            case .voice: return "Voice"
            }
        }
    }

    var id: UUID = UUID()
    var date: Date
    var kind: Kind
    var input: String
    var output: String
    var engine: String
    /// Put into the text (Apply, or a direct replace). Shown-only results (an explanation, a
    /// translation popup, a closed preview) are kept too, but the star does not offer them for
    /// inserting.
    var applied = true

    /// Appends `entry` keeping at most `limit` items, newest first. Pure and unit-tested.
    static func appending(_ entry: HistoryEntry, to list: [HistoryEntry], limit: Int) -> [HistoryEntry] {
        var result = [entry] + list
        if result.count > limit { result.removeLast(result.count - limit) }
        return result
    }
}

extension HistoryEntry: Codable {
    private enum CodingKeys: String, CodingKey { case id, date, kind, input, output, engine, applied }

    /// Entries from before `applied` existed were all results put into text.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        kind = try c.decode(Kind.self, forKey: .kind)
        input = try c.decode(String.self, forKey: .input)
        output = try c.decode(String.self, forKey: .output)
        engine = try c.decode(String.self, forKey: .engine)
        applied = try c.decodeIfPresent(Bool.self, forKey: .applied) ?? true
    }
}

/// Persists the last operations as JSON in Application Support. Main-actor: called from the
/// pipelines and read by the menu, both on the main thread.
@MainActor @Observable
final class HistoryStore {
    static let shared = HistoryStore()
    nonisolated static let limit = 50

    private(set) var entries: [HistoryEntry] = []
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = AppPaths.supportDirectory.appendingPathComponent("history.json")
        }
        load()
    }

    @discardableResult
    func record(kind: HistoryEntry.Kind, input: String, output: String, engine: String, applied: Bool = true) -> UUID {
        let entry = HistoryEntry(date: Date(), kind: kind, input: input, output: output, engine: engine, applied: applied)
        entries = HistoryEntry.appending(entry, to: entries, limit: Self.limit)
        save()
        return entry.id
    }

    func markApplied(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), !entries[index].applied else { return }
        entries[index].applied = true
        save()
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
