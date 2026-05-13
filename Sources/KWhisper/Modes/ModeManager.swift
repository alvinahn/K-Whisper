import Foundation
import Combine

@MainActor
final class ModeManager: ObservableObject {
    static let shared = ModeManager()

    @Published private(set) var modes: [Mode] = []

    private let storeURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("KWhisper", isDirectory: true)
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
        let mode = normalized(mode)
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
        // Persist user-defined modes verbatim across launches. For built-ins, keep
        // the code-owned prompt/name fresh but preserve the user's provider/model
        // choice so "Cleanup via Gemini" survives app updates and relaunches.
        var savedBuiltIns: [String: Mode]
        let savedUserModes: [Mode]
        if let data = try? Data(contentsOf: storeURL),
           let saved = try? JSONDecoder().decode([Mode].self, from: data) {
            savedBuiltIns = saved
                .filter(\.isBuiltIn)
                .reduce(into: [:]) { result, mode in result[mode.id] = mode }
            if savedBuiltIns["cleanup"] == nil, let legacyCleanup = savedBuiltIns["default-cleanup"] {
                var migrated = legacyCleanup
                migrated.id = "cleanup"
                savedBuiltIns["cleanup"] = migrated
            }
            savedUserModes = saved.filter { !$0.isBuiltIn }
        } else {
            savedBuiltIns = [:]
            savedUserModes = []
        }
        let builtIns = DefaultModes.all.map { builtIn -> Mode in
            guard let saved = savedBuiltIns[builtIn.id] else { return builtIn }
            var merged = builtIn
            merged.provider = saved.provider
            merged.model = saved.model
            merged.temperature = saved.temperature
            merged.maxTokens = saved.maxTokens
            return normalized(merged)
        }
        modes = builtIns + savedUserModes.map(normalized)
        persist()
    }

    private func normalized(_ mode: Mode) -> Mode {
        var mode = mode
        if mode.provider == .none {
            mode.model = ""
            mode.maxTokens = 0
        } else if mode.model.isEmpty || !DefaultModels.model(mode.model, matches: mode.provider) {
            mode.model = DefaultModels.defaultModel(for: mode.provider)
        }
        return mode
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(modes) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
