import Foundation
import Combine

/// User-managed glossary of proper nouns / brand terms / known names.
///
/// Storage shape stays as `[String]` for zero-migration backward compatibility.
/// Each line is parsed at read time using `|` syntax:
///   "결제 API"              → canonical "결제 API", no aliases
///   "결제 API|결재 API,결제 에이피아이" → canonical "결제 API", aliases ["결재 API", "결제 에이피아이"]
/// Aliases are alternate STT mishearings the user wants rewritten to the canonical
/// form deterministically (see `applySubstitutions(to:)`).
@MainActor
final class GlossaryStore: ObservableObject {
    static let shared = GlossaryStore()

    struct ParsedEntry {
        let canonical: String
        let aliases: [String]
    }

    @Published var terms: [String] {
        didSet { persist() }
    }

    private let storeURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("KWhisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("glossary.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: storeURL),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            self.terms = saved
        } else {
            self.terms = []
        }
    }

    /// Parse each raw term line into a canonical + alias list.
    func parsedEntries() -> [ParsedEntry] {
        terms.compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let canonical = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !canonical.isEmpty else { return nil }

            let aliases: [String]
            if parts.count > 1 {
                var seen = Set<String>()
                aliases = parts[1]
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0 != canonical && seen.insert($0).inserted }
            } else {
                aliases = []
            }
            return ParsedEntry(canonical: canonical, aliases: aliases)
        }
    }

    /// Canonical spellings only — used for both Whisper bias and LLM hint.
    /// Aliases are NEVER injected into model prompts (we don't want to reinforce
    /// the very mishearings we're trying to correct).
    func canonicalTerms() -> [String] {
        parsedEntries().map { $0.canonical }
    }

    /// Whisper API `prompt` param. Keep this short: dialect/style hints nudge the
    /// STT model toward spoken Korean, while canonical-only glossary entries are
    /// hints and alias mappings remain deterministic post-STT substitutions.
    func whisperBiasPrompt(language: String? = nil) -> String? {
        var parts: [String] = []

        if language != "en" {
            parts.append("한국어 구어체와 경상도 사투리가 포함될 수 있습니다. 실제 들리는 말투를 그대로 적어주세요. 예: 밥 문나, 뭐하노, 누구고, 맞나, 아이다, 한 것 같애.")
        }

        let canonicals = canonicalTerms()
        if !canonicals.isEmpty {
            let joined = canonicals.prefix(30).joined(separator: ", ")
            parts.append("자주 나오는 이름/용어: \(joined).")
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// For LLM post-processing: full list of canonical terms.
    func llmGlossaryBlock() -> String? {
        let canonicals = canonicalTerms()
        guard !canonicals.isEmpty else { return nil }
        return "Known terms (preserve their spelling): " + canonicals.joined(separator: ", ")
    }

    /// Deterministically rewrite any glossary aliases in `text` back to their canonical
    /// form, using Korean-aware word boundaries so that e.g. "옵션" is NOT corrupted to
    /// "고객센터장" just because "고객 센터" is an alias for "고객센터".
    ///
    /// Boundary rules:
    ///  - Pre-context: alias must NOT be preceded by a Hangul char (start, space,
    ///    English letter, or punctuation are all OK).
    ///  - Post-context: alias must be followed by end-of-string, a non-Hangul char,
    ///    or a known Korean particle.
    func applySubstitutions(to text: String) -> String {
        // Collect (alias, canonical) pairs from all entries with at least one alias.
        var pairs: [(alias: String, canonical: String)] = []
        for entry in parsedEntries() {
            for alias in entry.aliases {
                pairs.append((
                    alias: alias.precomposedStringWithCanonicalMapping,
                    canonical: entry.canonical
                ))
            }
        }
        guard !pairs.isEmpty else { return text }

        // Sort by descending alias length so longer aliases match before shorter ones
        // (prevents "미스" preempting "스미스").
        pairs.sort { $0.alias.count > $1.alias.count }

        // Lookup: matched substring → canonical replacement.
        var aliasToCanonical: [String: String] = [:]
        for pair in pairs where aliasToCanonical[pair.alias] == nil {
            aliasToCanonical[pair.alias] = pair.canonical
        }

        // Hangul-syllable range (precomposed) + Jamo blocks. `\p{Hangul}` is not
        // reliably supported in NSRegularExpression / ICU, so use literal Unicode
        // characters as range endpoints (these compile cleanly under ICU).
        let hangul = "가-힣\u{1100}-\u{11FF}\u{3130}-\u{318F}\u{A960}-\u{A97F}\u{D7B0}-\u{D7FF}"

        // Korean particles, sorted longest-first (ICU alternation is left-to-right).
        let particles = "이라고|이라는|이라서|이라며|에게서|한테서|에서|으로|에게|이라|이고|이며|까지|부터|밖에|보다|조차|마저|처럼|이|가|은|는|을|를|와|과|의|도|로|만|랑|께|요|야"

        let escapedAliases = pairs
            .map { NSRegularExpression.escapedPattern(for: $0.alias) }
            .joined(separator: "|")
        let pattern = "(?<![\(hangul)])(\(escapedAliases))(?=$|[^\(hangul)]|\(particles))"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            Log.stt.error("glossary regex compile failed for pattern: \(pattern)")
            return text
        }

        let normalized = text.precomposedStringWithCanonicalMapping
        let nsText = normalized as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // Single left-to-right pass: enumerateMatches + manual rebuild prevents any
        // re-substitution loop if a canonical happens to contain another alias.
        var result = ""
        var lastEnd = 0
        regex.enumerateMatches(in: normalized, range: fullRange) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 2 else { return }
            let aliasRange = match.range(at: 1)
            let matched = nsText.substring(with: aliasRange)
            guard let canonical = aliasToCanonical[matched] else { return }
            let mRange = match.range
            if mRange.location > lastEnd {
                result += nsText.substring(with: NSRange(location: lastEnd, length: mRange.location - lastEnd))
            }
            result += canonical
            lastEnd = mRange.location + mRange.length
        }
        if lastEnd < nsText.length {
            result += nsText.substring(with: NSRange(location: lastEnd, length: nsText.length - lastEnd))
        }
        return result
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(terms) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
