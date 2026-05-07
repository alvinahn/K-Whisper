import Foundation

enum STTProviderKind: String, CaseIterable, Codable, Identifiable {
    case groq           // Groq-hosted Whisper Large-v3-Turbo (recommended)
    case whisper        // OpenAI Whisper API (whisper-1, older v2-era)
    case gemini         // Google Gemini multimodal
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .groq:    return "Groq Whisper Large-v3-Turbo (recommended)"
        case .whisper: return "OpenAI Whisper (whisper-1)"
        case .gemini:  return "Google Gemini (audio)"
        }
    }
    var requiredKey: APIKeyKind {
        switch self {
        case .groq:    return .groq
        case .whisper: return .openai
        case .gemini:  return .google
        }
    }
}

struct TranscriptionResult {
    let text: String
    let language: String  // "ko" / "en" / etc.
    let durationMs: Int
}

protocol STTProvider {
    func transcribe(wav: Data, biasPrompt: String?) async throws -> TranscriptionResult
}

enum STTHelpers {
    /// Detect language by looking for Hangul characters; otherwise assume English.
    static func detectLanguage(from text: String) -> String {
        let hangul = text.range(of: "[\\u{AC00}-\\u{D7AF}]", options: .regularExpression) != nil
        return hangul ? "ko" : "en"
    }
}
