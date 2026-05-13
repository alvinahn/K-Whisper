import Foundation

/// Restores sentence-end punctuation (`?`, `!`, `.`) that the cleanup LLM may have
/// stripped from the STT-corrected text. Llama 70B occasionally drops Korean
/// confirmation `?` and terminal `.` even when the system prompt explicitly orders
/// "preserve all punctuation as transcribed" — this util is the deterministic safety
/// net for the conservative `default-cleanup` mode.
///
/// Behavior contract: **strictly additive**. Never modifies, replaces, or removes a
/// punctuation mark that already exists in `output`. If alignment fails (LLM rewrote
/// the surrounding text), the marker is silently dropped — better to under-restore
/// than to insert punctuation at the wrong position.
enum PunctuationRestorer {

    /// Marks we care about restoring when missing from output.
    private static let restorableMarks: Set<Character> = ["?", "!", "."]

    /// Marks that, if already present at the target position in output, count as
    /// "punctuation already there — don't add another one." Wider set than
    /// `restorableMarks` so we don't double up on commas or full-width variants.
    private static let anyTerminalChar: Set<Character> = [
        "?", "!", ".", ",", "~", "…",
        "？", "！", "。", "，"   // full-width / CJK variants
    ]

    /// Max characters BEFORE each mark to use as an alignment anchor. 5 is enough to
    /// be unique in almost any Korean sentence while still tolerating tiny LLM edits.
    private static let anchorLength = 5

    static func restore(input: String, output: String) -> String {
        guard !input.isEmpty, !output.isEmpty else { return output }

        let inputChars = Array(input)
        let outputChars = Array(output)

        // 1. Collect (mark, anchor) for each terminal punctuation in input.
        //    The anchor must NOT include earlier punctuation (which won't appear
        //    in the LLM's stripped output) — trim back past any prior mark.
        struct Marker {
            let mark: Character
            let anchor: [Character]
        }
        var markers: [Marker] = []
        for (idx, ch) in inputChars.enumerated() {
            guard restorableMarks.contains(ch) else { continue }
            let lowerBound = max(0, idx - anchorLength)
            var anchorStart = lowerBound
            for i in lowerBound..<idx where anyTerminalChar.contains(inputChars[i]) {
                anchorStart = i + 1
            }
            let raw = Array(inputChars[anchorStart..<idx])
            let trimmed = trimWhitespace(raw)
            guard !trimmed.isEmpty else { continue }
            markers.append(Marker(mark: ch, anchor: trimmed))
        }
        guard !markers.isEmpty else { return output }

        // 2. Walk output (immutable) finding each anchor in order, collecting
        //    insertion positions. Skip a marker if its anchor isn't found
        //    (LLM rewrote that section).
        var insertions: [(position: Int, mark: Character)] = []
        var searchFrom = 0
        for marker in markers {
            guard let matchStart = findSubarray(
                of: marker.anchor,
                in: outputChars,
                startingAt: searchFrom
            ) else {
                continue
            }
            let afterAnchor = matchStart + marker.anchor.count

            if afterAnchor < outputChars.count,
               anyTerminalChar.contains(outputChars[afterAnchor]) {
                // Some punctuation already there — don't double up.
                searchFrom = afterAnchor + 1
                continue
            }

            insertions.append((position: afterAnchor, mark: marker.mark))
            searchFrom = afterAnchor
        }

        guard !insertions.isEmpty else { return output }

        // 3. Apply insertions back-to-front so earlier positions stay valid.
        var resultChars = outputChars
        for ins in insertions.reversed() {
            resultChars.insert(ins.mark, at: ins.position)
        }
        return String(resultChars)
    }

    // MARK: - Helpers

    private static func trimWhitespace(_ chars: [Character]) -> [Character] {
        var start = 0
        var end = chars.count
        while start < end, chars[start].isWhitespace { start += 1 }
        while end > start, chars[end - 1].isWhitespace { end -= 1 }
        return Array(chars[start..<end])
    }

    private static func findSubarray<T: Equatable>(
        of needle: [T],
        in haystack: [T],
        startingAt: Int
    ) -> Int? {
        guard !needle.isEmpty,
              startingAt + needle.count <= haystack.count else { return nil }
        let lastStart = haystack.count - needle.count
        for s in startingAt...lastStart {
            var ok = true
            for i in 0..<needle.count where haystack[s + i] != needle[i] {
                ok = false
                break
            }
            if ok { return s }
        }
        return nil
    }
}
