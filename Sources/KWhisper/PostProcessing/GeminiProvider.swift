import Foundation

struct GeminiProvider: LLMProvider {
    let apiKey: String
    let session: URLSession

    init(apiKey: String, session: URLSession = Networking.shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func process(transcript: String, mode: Mode, system: String, user: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(mode.model):generateContent?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "system_instruction": [
                "parts": [["text": system]]
            ],
            "contents": [[
                "role": "user",
                "parts": [["text": user]]
            ]],
            "generationConfig": [
                "temperature": mode.temperature,
                "maxOutputTokens": mode.maxTokens > 0 ? mode.maxTokens : 1024
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw LLMError.http(-1, "no response") }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        struct Resp: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }
        do {
            let r = try JSONDecoder().decode(Resp.self, from: data)
            let text = r.candidates?.first?.content?.parts?.compactMap { $0.text }.joined() ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw LLMError.decode(error.localizedDescription)
        }
    }
}
