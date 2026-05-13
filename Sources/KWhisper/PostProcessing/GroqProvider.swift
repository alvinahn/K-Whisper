import Foundation

/// Groq-hosted Llama models for post-processing. OpenAI-compatible chat completions endpoint.
///
/// Default models for K-Whisper:
///  - `llama-3.1-8b-instant` for trivial rewrites (cleanup, short messages)
///    Typical TTFT: ~50ms, full response for ~30 tokens: ~100–250ms total
///  - `llama-3.3-70b-versatile` for email/translation
///    Typical TTFT: ~150ms, full response for ~80 tokens: ~250–500ms total
struct GroqProvider: LLMProvider {
    let apiKey: String
    let session: URLSession

    init(apiKey: String, session: URLSession = Networking.shared) {
        self.apiKey = apiKey
        self.session = session
    }

    // No model auto-fallback. Earlier attempt to swap a rate-limited 70B for 8B
    // produced catastrophic output (LLM treating dictation as a chat command,
    // hallucinating answers, leaking system prompt). On 429 we now surface the
    // rate-limit error cleanly — the user can switch to Verbatim mode or wait.

    func process(transcript: String, mode: Mode, system: String, user: String) async throws -> String {
        try await chatCompletion(model: mode.model, mode: mode, transcript: transcript, system: system, user: user)
    }

    private func chatCompletion(
        model: String,
        mode: Mode,
        transcript: String,
        system: String,
        user: String
    ) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let maxTokens = outputTokenBudget(for: transcript, mode: mode)
        let payload: [String: Any] = [
            "model": model,
            "temperature": mode.temperature,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await RateLimitRetry.data(for: req, session: session)
        guard let http = response as? HTTPURLResponse else { throw LLMError.http(-1, "no response") }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        struct Resp: Decodable {
            struct Usage: Decodable {
                let promptTokens: Int?
                let completionTokens: Int?
                let totalTokens: Int?

                enum CodingKeys: String, CodingKey {
                    case promptTokens = "prompt_tokens"
                    case completionTokens = "completion_tokens"
                    case totalTokens = "total_tokens"
                }
            }
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
            let usage: Usage?
        }
        do {
            let r = try JSONDecoder().decode(Resp.self, from: data)
            if let usage = r.usage {
                let prompt = usage.promptTokens.map(String.init) ?? "?"
                let completion = usage.completionTokens.map(String.init) ?? "?"
                let total = usage.totalTokens.map(String.init) ?? "?"
                Log.llm.info("Groq usage: prompt=\(prompt) completion=\(completion) total=\(total)")
            }
            let text = r.choices.first?.message.content ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw LLMError.decode(error.localizedDescription)
        }
    }

    private func outputTokenBudget(for transcript: String, mode: Mode) -> Int {
        let configured = mode.maxTokens > 0 ? mode.maxTokens : 1024
        guard mode.id == "cleanup" else { return configured }

        // Groq counts reserved output tokens against TPM. Cleanup output should be
        // close to the transcript length, so reserve less for short dictations while
        // keeping the built-in cap available for longer recordings.
        let estimatedCleanupTokens = Int((Double(transcript.count) * 1.5).rounded(.up)) + 32
        return min(configured, max(96, estimatedCleanupTokens))
    }
}
