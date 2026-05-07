import Foundation

/// OpenAI Whisper API client. Uses /v1/audio/transcriptions with verbose_json.
struct WhisperClient: STTProvider {
    enum WhisperError: Error, LocalizedError {
        case missingKey
        case http(Int, String)
        case decode(String)
        var errorDescription: String? {
            switch self {
            case .missingKey: return "OpenAI API key is missing. Add it in Settings → API Keys."
            case .http(let code, let body): return "Whisper — " + APIErrorParser.format(status: code, body: body)
            case .decode(let m): return "Whisper response decode failed: \(m)"
            }
        }
    }

    let apiKey: String
    let session: URLSession
    let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    init(apiKey: String, session: URLSession = Networking.shared) {
        self.apiKey = apiKey
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

        appendField(name: "model", value: "whisper-1")
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
            throw WhisperError.http(-1, "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw WhisperError.http(http.statusCode, text)
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
                language: v.language ?? "",
                durationMs: Int((v.duration ?? 0) * 1000)
            )
        } catch {
            throw WhisperError.decode(error.localizedDescription)
        }
    }
}
