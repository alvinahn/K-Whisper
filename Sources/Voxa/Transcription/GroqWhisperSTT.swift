import Foundation

/// Groq-hosted Whisper Large-v3-Turbo via their OpenAI-compatible audio transcription endpoint.
///
/// - Endpoint: `https://api.groq.com/openai/v1/audio/transcriptions`
/// - Default model: `whisper-large-v3-turbo` (216× realtime, $0.04/hr)
/// - Optional opt-in: `whisper-large-v3` (189× realtime, $0.111/hr) for slightly higher accuracy
///   on edge accents at ~2× cost.
///
/// Same wire format as OpenAI's Whisper, so the multipart shape mirrors `WhisperClient`.
struct GroqWhisperSTT: STTProvider {
    enum GroqSTTError: Error, LocalizedError {
        case missingKey
        case http(Int, String)
        case decode(String)
        var errorDescription: String? {
            switch self {
            case .missingKey: return "Groq API key is missing. Add it in Settings → API Keys."
            case .http(let c, let b): return "Groq STT error (\(c)): \(b)"
            case .decode(let m): return "Groq STT decode failed: \(m)"
            }
        }
    }

    let apiKey: String
    let model: String
    let session: URLSession
    let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!

    init(
        apiKey: String,
        model: String = "whisper-large-v3-turbo",
        session: URLSession = Networking.shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func transcribe(wav: Data, biasPrompt: String? = nil, language: String? = nil) async throws -> TranscriptionResult {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        func appendFile(name: String, filename: String, mime: String, data: Data) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }

        appendField(name: "model", value: model)
        appendField(name: "response_format", value: "verbose_json")
        appendField(name: "temperature", value: "0")
        if let bias = biasPrompt, !bias.isEmpty {
            appendField(name: "prompt", value: bias)
        }
        if let lang = language, !lang.isEmpty {
            appendField(name: "language", value: lang)
        }
        appendFile(name: "file", filename: "audio.wav", mime: "audio/wav", data: wav)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await session.upload(for: req, from: body)
        guard let http = response as? HTTPURLResponse else {
            throw GroqSTTError.http(-1, "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw GroqSTTError.http(http.statusCode, text)
        }

        struct Verbose: Decodable {
            let text: String
            let language: String?
            let duration: Double?
        }
        do {
            let v = try JSONDecoder().decode(Verbose.self, from: data)
            return TranscriptionResult(
                text: v.text.trimmingCharacters(in: .whitespacesAndNewlines),
                language: v.language ?? STTHelpers.detectLanguage(from: v.text),
                durationMs: Int((v.duration ?? 0) * 1000)
            )
        } catch {
            throw GroqSTTError.decode(error.localizedDescription)
        }
    }
}
