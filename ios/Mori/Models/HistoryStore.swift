import Foundation

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var url: String
    var platform: Platform?
    var result: MediaResult
    var date: Date
}

/// Analyze history, persisted as JSON in Application Support.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    private static let limit = 300

    @Published private(set) var entries: [HistoryEntry] = []

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    init() {
        if let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
        }
    }

    func add(url: String, platform: Platform?, result: MediaResult) {
        guard !AppSettings.shared.incognito else { return }
        entries.removeAll { $0.url == url }
        entries.insert(HistoryEntry(url: url, platform: platform, result: result, date: Date()), at: 0)
        if entries.count > Self.limit { entries = Array(entries.prefix(Self.limit)) }
        save()
    }

    func delete(_ ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        let snapshot = entries
        let url = fileURL
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
