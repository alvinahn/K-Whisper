import Foundation

enum DefaultModels {
    // Groq Llama models on LPU hardware — fastest TTFT in 2026.
    static let groqLlamaInstant   = "llama-3.1-8b-instant"      // ~50ms TTFT, ~100-250ms total
    static let groqLlamaVersatile = "llama-3.3-70b-versatile"   // ~150ms TTFT, ~250-500ms total

    // Other providers (kept as alternatives users can pick).
    static let claudeHaiku    = "claude-haiku-4-5"
    static let claudeSonnet   = "claude-sonnet-4-5"
    static let claudeOpus     = "claude-opus-4-5"
    static let openAIChat     = "gpt-4o-mini"
    static let geminiFlashLite = "gemini-2.5-flash-lite"
    static let geminiFlash    = "gemini-2.5-flash"
}

enum DefaultModes {
    static let all: [Mode] = [
        Mode(
            id: "default-cleanup",
            name: "Default cleanup",
            systemPrompt: "Clean filler words, fix punctuation/capitalization. Preserve meaning. Match input language (English or Korean). Output ONLY the cleaned transcript.",
            provider: .groq,
            model: DefaultModels.groqLlamaInstant,
            temperature: 0.2,
            maxTokens: 1024,
            isBuiltIn: true
        ),
        Mode(
            id: "email",
            name: "Email",
            systemPrompt: "Rewrite the transcript as a clear, concise email body. Match input language. No greeting/sign-off unless dictated. Output ONLY the email body.",
            provider: .groq,
            model: DefaultModels.groqLlamaVersatile,
            temperature: 0.3,
            maxTokens: 1024,
            isBuiltIn: true
        ),
        Mode(
            id: "slack",
            name: "Slack",
            systemPrompt: "Rewrite as a brief, casual Slack message. Match input language. No greeting/sign-off. One or two sentences. Output ONLY the message.",
            provider: .groq,
            model: DefaultModels.groqLlamaInstant,
            temperature: 0.4,
            maxTokens: 512,
            isBuiltIn: true
        ),
        Mode(
            id: "ko-to-en",
            name: "Korean → English",
            systemPrompt: "Translate Korean to natural, idiomatic English. Keep technical terms in English. Match the register of the source. Output ONLY the translation.",
            provider: .groq,
            model: DefaultModels.groqLlamaVersatile,
            temperature: 0.2,
            maxTokens: 1024,
            isBuiltIn: true
        ),
        Mode(
            id: "en-to-ko",
            name: "English → Korean",
            systemPrompt: "Translate English to natural Korean. Default tone: {KOREAN_TONE}. Keep proper nouns and technical terms in original form. Output ONLY the translation.",
            provider: .groq,
            model: DefaultModels.groqLlamaVersatile,
            temperature: 0.2,
            maxTokens: 1024,
            isBuiltIn: true
        ),
        Mode(
            id: "code-comment",
            name: "Code comment",
            systemPrompt: "Convert to a terse code comment. One line if possible. No markdown, no quotes. English unless the speaker asked for Korean. Output ONLY the comment text without comment markers.",
            provider: .groq,
            model: DefaultModels.groqLlamaInstant,
            temperature: 0.2,
            maxTokens: 256,
            isBuiltIn: true
        ),
        Mode(
            id: "raw",
            name: "Raw (no post-processing)",
            systemPrompt: "",
            provider: .none,
            model: "",
            temperature: 0,
            maxTokens: 0,
            isBuiltIn: true
        )
    ]
}
