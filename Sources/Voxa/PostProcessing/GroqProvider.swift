import Foundation

/// Groq-hosted Llama models for post-processing. OpenAI-compatible chat completions endpoint.
///
/// Default models for Voxa:
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

    func process(transcript: String, mode: Mode, system: String, user: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": mode.model,
            "temperature": mode.temperature,
            "max_tokens": mode.maxTokens > 0 ? mode.maxTokens : 1024,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw LLMError.http(-1, "no response") }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        struct Resp: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        do {
            let r = try JSONDecoder().decode(Resp.self, from: data)
            let text = r.choices.first?.message.content ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw LLMError.decode(error.localizedDescription)
        }
    }
}
