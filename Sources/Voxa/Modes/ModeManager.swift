import Foundation
import Combine

@MainActor
final class ModeManager: ObservableObject {
    static let shared = ModeManager()

    @Published private(set) var modes: [Mode] = []

    private let storeURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Voxa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("modes.json")
    }()

    private init() {
        load()
    }

    func mode(id: String) -> Mode? {
        modes.first(where: { $0.id == id })
    }

    func upsert(_ mode: Mode) {
        if let idx = modes.firstIndex(where: { $0.id == mode.id }) {
            modes[idx] = mode
        } else {
            modes.append(mode)
        }
        persist()
    }

    func delete(id: String) {
        guard let m = mode(id: id), !m.isBuiltIn else { return }
        modes.removeAll { $0.id == id }
        persist()
    }

    func resetToDefaults() {
        modes = DefaultModes.all
        persist()
    }

    private func load() {
        // Always source built-in modes from code (so model/provider updates ship with the app).
        // Persist user-defined modes verbatim across launches.
        let savedUserModes: [Mode]
        if let data = try? Data(contentsOf: storeURL),
           let saved = try? JSONDecoder().decode([Mode].self, from: data) {
            savedUserModes = saved.filter { !$0.isBuiltIn }
        } else {
            savedUserModes = []
        }
        modes = DefaultModes.all + savedUserModes
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(modes) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
