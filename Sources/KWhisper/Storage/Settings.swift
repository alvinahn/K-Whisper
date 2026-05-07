import Foundation
import Combine

enum OutputMethod: String, CaseIterable, Identifiable, Codable {
    case clipboardPaste
    case syntheticTyping
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .clipboardPaste: return "Clipboard paste (⌘V)"
        case .syntheticTyping: return "Synthetic typing"
        }
    }
}

enum KoreanTone: String, CaseIterable, Identifiable, Codable {
    case banmal
    case jondaetmal
    case auto
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .banmal: return "반말 (casual)"
        case .jondaetmal: return "존댓말 (polite)"
        case .auto: return "Auto-detect from context"
        }
    }
}

enum AudioLanguage: String, CaseIterable, Identifiable, Codable {
    case auto
    case ko
    case en
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .ko:   return "Korean (한국어)"
        case .en:   return "English"
        }
    }
    /// ISO-639-1 code Whisper expects, or nil for auto-detect.
    var whisperCode: String? {
        switch self {
        case .auto: return nil
        case .ko:   return "ko"
        case .en:   return "en"
        }
    }
}

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    @Published var defaultModeId: String {
        didSet { UserDefaults.standard.set(defaultModeId, forKey: "defaultModeId") }
    }
    @Published var outputMethod: OutputMethod {
        didSet { UserDefaults.standard.set(outputMethod.rawValue, forKey: "outputMethod") }
    }
    @Published var koreanTone: KoreanTone {
        didSet { UserDefaults.standard.set(koreanTone.rawValue, forKey: "koreanTone") }
    }
    @Published var toggleHotkeyKeyCode: Int {
        didSet { UserDefaults.standard.set(toggleHotkeyKeyCode, forKey: "toggleHotkeyKeyCode") }
    }
    @Published var toggleHotkeyModifiers: Int {
        didSet { UserDefaults.standard.set(toggleHotkeyModifiers, forKey: "toggleHotkeyModifiers") }
    }
    @Published var holdKeyEnabled: Bool {
        didSet { UserDefaults.standard.set(holdKeyEnabled, forKey: "holdKeyEnabled") }
    }
    @Published var holdKey: HoldKey {
        didSet { UserDefaults.standard.set(holdKey.rawValue, forKey: "holdKey") }
    }
    @Published var playSounds: Bool {
        didSet { UserDefaults.standard.set(playSounds, forKey: "playSounds") }
    }
    @Published var streamOutput: Bool {
        didSet { UserDefaults.standard.set(streamOutput, forKey: "streamOutput") }
    }
    @Published var sttProvider: STTProviderKind {
        didSet { UserDefaults.standard.set(sttProvider.rawValue, forKey: "sttProvider") }
    }
    @Published var audioLanguage: AudioLanguage {
        didSet { UserDefaults.standard.set(audioLanguage.rawValue, forKey: "audioLanguage") }
    }

    private init() {
        let d = UserDefaults.standard

        // One-shot settings migration. Bump `settingsMigrationVersion` to apply a new default
        // forcibly (overriding any persisted value from earlier app versions).
        let migrationVersion = d.integer(forKey: "settingsMigrationVersion")
        if migrationVersion < 1 {
            // v1: switch start/stop sounds OFF by default for everyone.
            d.set(false, forKey: "playSounds")
            d.set(1, forKey: "settingsMigrationVersion")
        }

        self.defaultModeId = d.string(forKey: "defaultModeId") ?? "default-cleanup"
        self.outputMethod = OutputMethod(rawValue: d.string(forKey: "outputMethod") ?? "")
            ?? .clipboardPaste
        self.koreanTone = KoreanTone(rawValue: d.string(forKey: "koreanTone") ?? "")
            ?? .auto
        // ⌥⌘Space default — keyCode 49 is Space, modifiers = option(2048) | command(256) raw mask
        self.toggleHotkeyKeyCode = d.object(forKey: "toggleHotkeyKeyCode") as? Int ?? 49
        self.toggleHotkeyModifiers = d.object(forKey: "toggleHotkeyModifiers") as? Int
            ?? (1 << 11 | 1 << 8)  // optionKey | cmdKey (Carbon constants)
        self.holdKeyEnabled = d.object(forKey: "holdKeyEnabled") as? Bool ?? true
        self.holdKey = HoldKey(rawValue: d.string(forKey: "holdKey") ?? "") ?? .rightCommand
        self.playSounds = d.object(forKey: "playSounds") as? Bool ?? false
        self.streamOutput = d.object(forKey: "streamOutput") as? Bool ?? false
        self.sttProvider = STTProviderKind(rawValue: d.string(forKey: "sttProvider") ?? "") ?? .groq
        self.audioLanguage = AudioLanguage(rawValue: d.string(forKey: "audioLanguage") ?? "") ?? .auto
    }
}
