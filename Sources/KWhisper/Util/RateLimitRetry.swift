import Foundation

/// Performs URLSession requests with one automatic retry when the server returns
/// HTTP 429 Rate Limited. Honors the `Retry-After` header; falls back to parsing
/// "try again in N s/ms" from the response body (Groq emits this); defaults to 2 s
/// when neither is present. If the requested wait is longer than `maxWait`, the
/// 429 is surfaced immediately so the UI doesn't freeze for a long time during
/// interactive dictation.
///
/// Used by both Groq providers (STT + LLM) so a brief burst over the free-tier
/// limit auto-recovers instead of bubbling up as a user-facing error.
///
/// `maxWait` is 15 s — Groq free-tier 70B (12K TPM) typically asks for ~10–13 s
/// when a burst exceeds the per-minute bucket. The previous 5 s cap meant the
/// retry usually fired before the bucket refilled and hit a second 429, making
/// the retry useless. 15 s gives the bucket time to actually refill while still
/// bounding worst-case dictation latency.
enum RateLimitRetry {

    static let maxWait: Double = 15.0
    static let defaultWait: Double = 2.0

    /// Wraps `URLSession.data(for:)` with one 429 retry.
    static func data(
        for request: URLRequest,
        session: URLSession
    ) async throws -> (Data, URLResponse) {
        try await perform { try await session.data(for: request) }
    }

    /// Wraps `URLSession.upload(for:from:)` with one 429 retry.
    static func upload(
        for request: URLRequest,
        from body: Data,
        session: URLSession
    ) async throws -> (Data, URLResponse) {
        try await perform { try await session.upload(for: request, from: body) }
    }

    // MARK: - Internal

    private static func perform(
        _ call: () async throws -> (Data, URLResponse)
    ) async throws -> (Data, URLResponse) {
        let (firstData, firstResponse) = try await call()
        guard let http = firstResponse as? HTTPURLResponse,
              http.statusCode == 429 else {
            return (firstData, firstResponse)
        }

        let wait = requestedWaitSeconds(from: http, body: firstData)
        guard wait <= maxWait else {
            Log.app.info("rate limited — server asked to retry in \(String(format: "%.1f", wait))s; surfacing 429")
            return (firstData, firstResponse)
        }

        Log.app.info("rate limited — retrying once in \(String(format: "%.1f", wait))s")
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))

        // Single retry attempt. Whatever we get back is final — don't retry again.
        return try await call()
    }

    private static func requestedWaitSeconds(from response: HTTPURLResponse, body: Data) -> Double {
        // 1. Standard `Retry-After` header (seconds).
        if let header = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(header.trimmingCharacters(in: .whitespaces)) {
            return max(seconds, 0.1)
        }

        // 2. Groq emits "Please try again in 1.23s" or "in 456ms" in the JSON body.
        if let text = String(data: body, encoding: .utf8) {
            if let s = extract(pattern: #"try again in ([0-9]+\.?[0-9]*)\s*s\b"#, in: text),
               let v = Double(s) {
                return max(v, 0.1)
            }
            if let s = extract(pattern: #"try again in ([0-9]+\.?[0-9]*)\s*ms\b"#, in: text),
               let v = Double(s) {
                return max(v / 1000.0, 0.1)
            }
        }

        return defaultWait
    }

    private static func extract(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}
