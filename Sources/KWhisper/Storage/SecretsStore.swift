import Foundation
import Combine

enum APIKeyKind: String, CaseIterable, Identifiable {
    case openai
    case anthropic
    case google
    case groq
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .openai:    return "OpenAI"
        case .anthropic: return "Anthropic (Claude)"
        case .google:    return "Google (Gemini)"
        case .groq:      return "Groq"
        }
    }
}

/// File-backed secrets store.
///
/// API keys are written to `~/Library/Application Support/KWhisper/secrets.json` with
/// POSIX permissions 0600 (owner-only). This avoids macOS Keychain re-authorization
/// prompts that would otherwise appear after every rebuild of an unsigned app, and
/// matches the "config file with restricted permissions" pattern used by most CLIs.
///
/// Threat model: we trust other processes running as the same user. If you don't
/// trust other apps you've installed, use the keychain version (deprecated) or a
/// hardware-backed solution instead.
@MainActor
final class SecretsStore: ObservableObject {
    static let shared = SecretsStore()

    @Published private(set) var hasOpenAI: Bool = false
    @Published private(set) var hasAnthropic: Bool = false
    @Published private(set) var hasGoogle: Bool = false
    @Published private(set) var hasGroq: Bool = false

    private let fileURL: URL
    private var secrets: [String: String] = [:]

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("KWhisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("secrets.json")
        load()
    }

    var storagePath: String { fileURL.path }

    func get(_ kind: APIKeyKind) -> String? {
        secrets[kind.rawValue]
    }

    func set(_ kind: APIKeyKind, value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            secrets.removeValue(forKey: kind.rawValue)
        } else {
            secrets[kind.rawValue] = trimmed
        }
        try persist()
        refreshFlags()
    }

    func clear(_ kind: APIKeyKind) {
        secrets.removeValue(forKey: kind.rawValue)
        try? persist()
        refreshFlags()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        secrets = dict
        refreshFlags()
    }

    private func persist() throws {
        let data = try JSONSerialization.data(
            withJSONObject: secrets,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: fileURL, options: [.atomic])
        // Owner read/write only.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private func refreshFlags() {
        hasOpenAI    = secrets[APIKeyKind.openai.rawValue] != nil
        hasAnthropic = secrets[APIKeyKind.anthropic.rawValue] != nil
        hasGoogle    = secrets[APIKeyKind.google.rawValue] != nil
        hasGroq      = secrets[APIKeyKind.groq.rawValue] != nil
    }
}
