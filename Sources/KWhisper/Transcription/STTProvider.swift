import Foundation

enum STTProviderKind: String, CaseIterable, Codable, Identifiable {
    case groq           // Groq-hosted Whisper Large-v3-Turbo (distilled, fastest, recommended)
    case groqV3         // Groq-hosted Whisper Large-v3 (full — slightly better Korean ?/intonation)
    case whisper        // OpenAI Whisper API (whisper-1, older v2-era)
    case gemini         // Google Gemini multimodal
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .groq:    return "Groq Whisper Large-v3-Turbo (추천)"
        case .groqV3:  return "Groq Whisper Large-v3 (정확도 우선)"
        case .whisper: return "OpenAI Whisper (whisper-1)"
        case .gemini:  return "Google Gemini"
        }
    }
    var requiredKey: APIKeyKind {
        switch self {
        case .groq, .groqV3: return .groq
        case .whisper:       return .openai
        case .gemini:        return .google
        }
    }
}

struct TranscriptionResult {
    let text: String
    let language: String  // "ko" / "en" / etc.
    let durationMs: Int
}

protocol STTProvider {
    /// - Parameters:
    ///   - wav: 16 kHz mono Int16 WAV data
    ///   - biasPrompt: optional Whisper-style spelling/glossary bias (~224 token budget)
    ///   - language: ISO-639-1 code (e.g., "ko", "en") or nil for auto-detect.
    ///     Forcing language reduces Korean errors when audio is known-Korean.
    func transcribe(wav: Data, biasPrompt: String?, language: String?) async throws -> TranscriptionResult
}

extension STTProvider {
    func transcribe(wav: Data, biasPrompt: String? = nil) async throws -> TranscriptionResult {
        try await transcribe(wav: wav, biasPrompt: biasPrompt, language: nil)
    }
}

enum STTHelpers {
    /// Detect language by looking for Hangul characters; otherwise assume English.
    static func detectLanguage(from text: String) -> String {
        let hangul = text.range(of: "[\\u{AC00}-\\u{D7AF}]", options: .regularExpression) != nil
        return hangul ? "ko" : "en"
    }
}
