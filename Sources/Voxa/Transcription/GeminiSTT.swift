import Foundation

/// Uses Gemini 2.5 Flash multimodal audio input for transcription.
/// Free for personal use under the Gemini API free tier.
struct GeminiSTT: STTProvider {
    enum GeminiSTTError: Error, LocalizedError {
        case missingKey
        case http(Int, String)
        case decode(String)
        case empty
        var errorDescription: String? {
            switch self {
            case .missingKey: return "Google (Gemini) API key is missing. Add it in Settings → API Keys."
            case .http(let c, let b): return "Gemini STT error (\(c)): \(b)"
            case .decode(let m): return "Gemini STT decode failed: \(m)"
            case .empty: return "Gemini STT returned no text."
            }
        }
    }

    let apiKey: String
    let model: String
    let session: URLSession

    init(apiKey: String, model: String = "gemini-2.5-flash", session: URLSession = Networking.shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func transcribe(wav: Data, biasPrompt: String? = nil) async throws -> TranscriptionResult {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var promptText = """
        Transcribe this audio verbatim into text.
        - Language can be Korean (한국어) or English. Detect automatically and transcribe in the same language as spoken.
        - Output ONLY the transcript with no preamble, quotes, or commentary.
        - Do NOT translate. Do NOT clean up filler words.
        """
        if let bias = biasPrompt, !bias.isEmpty {
            promptText += "\n\nKnown terms to spell correctly: \(bias)"
        }

        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": promptText],
                    ["inline_data": [
                        "mime_type": "audio/wav",
                        "data": wav.base64EncodedString()
                    ]]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.0,
                "maxOutputTokens": 2048
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GeminiSTTError.http(-1, "no response") }
        guard (200..<300).contains(http.statusCode) else {
            throw GeminiSTTError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
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
        let r: Resp
        do {
            r = try JSONDecoder().decode(Resp.self, from: data)
        } catch {
            throw GeminiSTTError.decode(error.localizedDescription)
        }

        let text = r.candidates?.first?.content?.parts?.compactMap { $0.text }.joined() ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GeminiSTTError.empty }

        return TranscriptionResult(
            text: trimmed,
            language: STTHelpers.detectLanguage(from: trimmed),
            durationMs: 0  // Gemini doesn't report duration
        )
    }
}
