import Foundation
import Combine

struct HistoryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let modeId: String
    let modeName: String
    let language: String
    let durationMs: Int
    let rawTranscript: String
    let processedText: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        modeId: String,
        modeName: String,
        language: String,
        durationMs: Int,
        rawTranscript: String,
        processedText: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.modeId = modeId
        self.modeName = modeName
        self.language = language
        self.durationMs = durationMs
        self.rawTranscript = rawTranscript
        self.processedText = processedText
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    static let maxEntries = 500

    @Published private(set) var entries: [HistoryEntry] = []

    private let storeURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("KWhisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    private init() {
        load()
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func load() {
        if let data = try? Data(contentsOf: storeURL),
           let saved = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = saved
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
