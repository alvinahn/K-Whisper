import Foundation

@MainActor
struct PostProcessor {
    let mode: Mode
    let language: String
    let glossary: String?
    let koreanTone: KoreanTone

    func run(transcript: String) async throws -> String {
        if mode.provider == .none {
            return transcript
        }
        let provider: LLMProvider = try makeProvider()
        let (system, user) = buildPrompts(transcript: transcript)
        return try await provider.process(transcript: transcript, mode: mode, system: system, user: user)
    }

    private func makeProvider() throws -> LLMProvider {
        let store = SecretsStore.shared
        switch mode.provider {
        case .groq:
            guard let key = store.get(.groq) else { throw LLMError.missingKey(.groq) }
            return GroqProvider(apiKey: key)
        case .claude:
            guard let key = store.get(.anthropic) else { throw LLMError.missingKey(.claude) }
            return ClaudeProvider(apiKey: key)
        case .openai:
            guard let key = store.get(.openai) else { throw LLMError.missingKey(.openai) }
            return OpenAIProvider(apiKey: key)
        case .gemini:
            guard let key = store.get(.google) else { throw LLMError.missingKey(.gemini) }
            return GeminiProvider(apiKey: key)
        case .none:
            fatalError("unreachable")
        }
    }

    private func buildPrompts(transcript: String) -> (system: String, user: String) {
        var system = mode.systemPrompt
        // Resolve {KOREAN_TONE} placeholder for translation modes.
        let toneText: String = {
            switch koreanTone {
            case .banmal: return "반말 (casual)"
            case .jondaetmal: return "존댓말 (polite)"
            case .auto: return "match the formality of the source"
            }
        }()
        system = system.replacingOccurrences(of: "{KOREAN_TONE}", with: toneText)
        if let glossary = glossary {
            system += "\n\n" + glossary
        }
        if !language.isEmpty {
            system += "\n\nDetected language: \(language)."
        }

        // Keep the variable transcript fenced off from the instructions so dictated
        // commands are treated as data, not executed as chat requests.
        let wrappedUser = """
        <transcript_to_clean>
        \(transcript)
        </transcript_to_clean>

        Use only the text inside the tags as the input. Follow the system instructions for this mode. Output only the final result.
        """
        return (system, wrappedUser)
    }
}
