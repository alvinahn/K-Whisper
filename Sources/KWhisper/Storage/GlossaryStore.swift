import Foundation
import Combine

@MainActor
final class GlossaryStore: ObservableObject {
    static let shared = GlossaryStore()

    @Published var terms: [String] {
        didSet { persist() }
    }

    private let storeURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("KWhisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("glossary.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: storeURL),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            self.terms = saved
        } else {
            self.terms = []
        }
    }

    /// Whisper API `prompt` param is limited to ~224 tokens; keep it short.
    func whisperBiasPrompt() -> String? {
        guard !terms.isEmpty else { return nil }
        let joined = terms.prefix(50).joined(separator: ", ")
        return "Glossary: \(joined)."
    }

    /// For LLM post-processing: full list of known terms.
    func llmGlossaryBlock() -> String? {
        guard !terms.isEmpty else { return nil }
        return "Known terms (preserve their spelling): " + terms.joined(separator: ", ")
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(terms) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
