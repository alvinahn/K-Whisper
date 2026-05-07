import Foundation
import AppKit
import Carbon.HIToolbox
import ApplicationServices

@MainActor
enum TextInjector {

    enum DeliveryError: Error, LocalizedError {
        case accessibilityNotGranted
        var errorDescription: String? {
            switch self {
            case .accessibilityNotGranted:
                return "Accessibility permission missing — paste can't reach the focused app"
            }
        }
    }

    /// Pastes text at the current cursor by:
    ///   1) saving current pasteboard (string only),
    ///   2) writing `text`,
    ///   3) posting Cmd+V to the focused app,
    ///   4) restoring the original clipboard ~250ms later.
    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postCmdV()

        // Restore clipboard after the paste has happened. 80ms is enough for the
        // focused app to consume Cmd+V; saves ~170ms perceived latency vs the prior 250ms.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            pasteboard.clearContents()
            if let saved = saved {
                pasteboard.setString(saved, forType: .string)
            }
        }
    }

    /// Synthesizes Unicode keystrokes for the text. Slower; used as a fallback.
    static func type(_ text: String) {
        let chunkSize = 20
        var offset = text.startIndex
        while offset < text.endIndex {
            let end = text.index(offset, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            let chunk = String(text[offset..<end])
            offset = end

            let utf16 = Array(chunk.utf16)
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            utf16.withUnsafeBufferPointer { ptr in
                down?.keyboardSetUnicodeString(stringLength: ptr.count, unicodeString: ptr.baseAddress)
                up?.keyboardSetUnicodeString(stringLength: ptr.count, unicodeString: ptr.baseAddress)
            }
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    private static func postCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        // V key code = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Routes through the user-selected output method.
    /// Throws if Accessibility permission is missing — without it, the synthesized
    /// keystrokes/paste are silently swallowed by macOS, and the user sees a fake-success HUD.
    static func deliver(_ text: String) throws {
        let cleaned = dedupeExactDoubling(text)
        guard !cleaned.isEmpty else { return }
        guard AXIsProcessTrusted() else {
            Log.inject.error("AXIsProcessTrusted is false — paste cannot reach the focused app")
            throw DeliveryError.accessibilityNotGranted
        }
        switch Settings.shared.outputMethod {
        case .clipboardPaste:
            paste(cleaned)
        case .syntheticTyping:
            type(cleaned)
        }
    }

    /// Detects and removes the case where an LLM cleanup pass returned the same text
    /// concatenated with itself (no separator). This sometimes happens with Llama 70B on
    /// Korean inputs where it echoes the original alongside the cleaned version. We catch
    /// it as a final safety net so the user never sees the same paragraph pasted twice.
    static func dedupeExactDoubling(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = trimmed.count
        guard n > 8, n % 2 == 0 else { return text }
        let mid = trimmed.index(trimmed.startIndex, offsetBy: n / 2)
        let firstHalf = trimmed[trimmed.startIndex..<mid]
        let secondHalf = trimmed[mid..<trimmed.endIndex]
        if firstHalf == secondHalf {
            Log.inject.warning("Detected exact text duplication; deduping (\(n) → \(n / 2) chars)")
            return String(firstHalf)
        }
        return text
    }
}
