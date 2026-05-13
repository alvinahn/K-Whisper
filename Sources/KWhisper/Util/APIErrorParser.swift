import Foundation

/// Turns raw HTTP error responses from STT/LLM providers into short, human-readable strings.
///
/// All major providers (OpenAI, Groq, Anthropic, Google) return JSON of the shape:
///   `{"error": {"message": "...", "type": "...", "code": "..."}}`
///
/// We extract `error.message`, prepend a friendly status-code category, and produce a
/// short two-part error: a short title and an optional actionable hint.
enum APIErrorParser {

    /// One-line error string for the HUD: "Category: message".
    static func format(status: Int, body: String) -> String {
        let category = categoryName(for: status)
        let detail = status == 429 ? parseRateLimitMessage(from: body) : parseMessage(from: body)
        if detail.isEmpty { return category }
        return "\(category): \(detail)"
    }

    /// Returns a short actionable hint for common status codes (or nil if none).
    static func hint(status: Int) -> String? {
        hint(status: status, body: "")
    }

    /// Returns a short actionable hint, using provider body details when available.
    static func hint(status: Int, body: String) -> String? {
        switch status {
        case 400: return "조금 더 길게 말한 뒤 다시 시도하세요."
        case 401: return "설정 → API 키를 확인하세요."
        case 403: return "이 API 키는 해당 모델 권한이 없습니다."
        case 408, 504: return "네트워크가 느립니다. 다시 시도하세요."
        case 413: return "오디오 파일이 너무 큽니다."
        case 429: return rateLimitHint(from: body)
        case 500..<600: return "서비스 서버 문제입니다. 다시 시도하세요."
        default: return nil
        }
    }

    /// Maps `URLError` (transport-level failures: offline, timeout, DNS, etc.) into
    /// a human-friendly title + hint pair. Returns nil for codes we don't want to
    /// surface as user-facing errors (e.g. `.cancelled` is a user action, not an error).
    static func urlError(_ error: URLError) -> (title: String, hint: String)? {
        switch error.code {
        case .cancelled:
            return nil  // user cancelled — handled separately, no HUD error
        case .notConnectedToInternet:
            return ("인터넷 연결 없음", "Wi-Fi를 확인하세요 · Esc로 닫기")
        case .networkConnectionLost:
            return ("네트워크 연결 끊김", "다시 시도하세요 · Esc로 닫기")
        case .timedOut:
            return ("요청 시간 초과", "네트워크가 느립니다 · 다시 시도")
        case .cannotFindHost, .dnsLookupFailed:
            return ("서버에 연결할 수 없음 (DNS)", "연결을 확인하세요 · Esc로 닫기")
        case .cannotConnectToHost:
            return ("서버에 연결할 수 없음", "서비스 장애일 수 있습니다 · 다시 시도")
        case .internationalRoamingOff, .callIsActive, .dataNotAllowed:
            return ("네트워크 사용 불가", "연결을 확인하세요 · Esc로 닫기")
        case .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired:
            return ("보안 연결 실패", "TLS 오류 · 시스템 시간을 확인하세요")
        default:
            return ("네트워크 오류", error.localizedDescription)
        }
    }

    // MARK: - Internals

    private static func parseMessage(from body: String) -> String {
        let message = providerMessage(from: body)
        return clipped(message, to: 180)
    }

    private static func parseRateLimitMessage(from body: String) -> String {
        let message = providerMessage(from: body)
        guard !message.isEmpty else { return "" }

        let model = extract(pattern: #"model `([^`]+)`"#, in: message)
            ?? extract(pattern: #"model "?([A-Za-z0-9._/\-]+)"?"#, in: message)
        let dimension = extract(pattern: #"on ([^:]+):"#, in: message)
        let shortDimension = dimension.flatMap { extract(pattern: #"\(([A-Z]+)\)"#, in: $0) } ?? dimension
        let limit = extract(pattern: #"Limit ([0-9,]+)"#, in: message)
        let used = extract(pattern: #"Used ([0-9,]+)"#, in: message)
        let requested = extract(pattern: #"Requested ([0-9,]+)"#, in: message)
        let waitSeconds = extract(pattern: #"try again in ([0-9]+\.?[0-9]*)\s*s\b"#, in: message)
        let waitMillis = extract(pattern: #"try again in ([0-9]+\.?[0-9]*)\s*ms\b"#, in: message)

        var parts: [String] = []
        if let model {
            parts.append(model)
        }
        if let shortDimension {
            parts.append("\(shortDimension) 한도")
        }
        if let used, let limit {
            parts.append("사용 \(used)/\(limit)")
        }
        if let requested {
            parts.append("요청 \(requested)")
        }
        if let waitSeconds {
            parts.append("\(waitSeconds)초 뒤 재시도")
        } else if let waitMillis {
            parts.append("\(waitMillis)ms 뒤 재시도")
        }

        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }
        return clipped(message, to: 220)
    }

    private static func rateLimitHint(from body: String) -> String {
        let message = providerMessage(from: body)
        let dimension = extract(pattern: #"on ([^:]+):"#, in: message)
        let shortDimension = dimension.flatMap { extract(pattern: #"\(([A-Z]+)\)"#, in: $0) } ?? dimension

        switch shortDimension?.uppercased() {
        case "TPD":
            return "일일 모델 토큰 한도 · 내일 초기화됩니다."
        case "TPM":
            return "분당 모델 토큰 한도 · 초기화를 기다리세요."
        case "RPD":
            return "일일 요청 한도 · 내일 초기화됩니다."
        case "RPM":
            return "분당 요청 한도 · 초기화를 기다리세요."
        default:
            return "모델 사용량 한도 · 초기화를 기다리세요."
        }
    }

    private static func providerMessage(from body: String) -> String {
        // Try OpenAI / Groq / Anthropic / Gemini JSON shape: {"error":{"message":"..."}}.
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Anthropic also sometimes returns top-level `{"type":"error","error":{...}}` — covered above.
        // Fallback: return a small slice of the raw body.
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clipped(_ text: String, to maxLength: Int) -> String {
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func extract(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func categoryName(for status: Int) -> String {
        switch status {
        case 400: return "잘못된 요청"
        case 401: return "API 키 오류"
        case 403: return "권한 없음"
        case 404: return "요청 주소 없음"
        case 408: return "요청 시간 초과"
        case 413: return "오디오가 너무 큼"
        case 429: return "사용량 한도 초과"
        case 500: return "서버 오류"
        case 502: return "서버 연결 오류"
        case 503: return "서비스 사용 불가"
        case 504: return "서버 응답 시간 초과"
        case 500..<600: return "서버 오류 \(status)"
        case -1: return "응답 없음"
        default: return "HTTP \(status)"
        }
    }
}
