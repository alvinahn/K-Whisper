import Foundation

struct ClaudeProvider: LLMProvider {
    let apiKey: String
    let session: URLSession

    init(apiKey: String, session: URLSession = Networking.shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func process(transcript: String, mode: Mode, system: String, user: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let payload: [String: Any] = [
            "model": mode.model,
            "max_tokens": mode.maxTokens > 0 ? mode.maxTokens : 1024,
            "temperature": mode.temperature,
            "system": system,
            "messages": [
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
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        do {
            let r = try JSONDecoder().decode(Resp.self, from: data)
            let combined = r.content.compactMap { $0.text }.joined()
            return combined.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw LLMError.decode(error.localizedDescription)
        }
    }
}
