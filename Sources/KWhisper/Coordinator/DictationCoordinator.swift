import Foundation
import AppKit
import Combine

@MainActor
final class DictationCoordinator: ObservableObject {
    static let shared = DictationCoordinator()

    enum RecordingTrigger: Equatable {
        case toggle  // entered via tap/toggle hotkey — exit on next tap or Esc
        case hold    // entered via push-to-talk hold — exit on key release
    }

    enum State: Equatable {
        case idle
        case recording(modeId: String, trigger: RecordingTrigger)
        case processing
    }

    @Published private(set) var state: State = .idle

    private let recorder = AudioRecorder()
    private let hotkey = HotkeyManager()
    private let hud = HUDWindowController.shared
    private let modes = ModeManager.shared
    private let glossary = GlossaryStore.shared
    private let history = HistoryStore.shared
    private let settings = Settings.shared
    private let keychain = SecretsStore.shared

    private var nextModeId: String?  // overrides default for the next dictation
    private var elapsedSubscription: AnyCancellable?
    private var levelSubscription: AnyCancellable?

    private init() {}

    func start() {
        hotkey.onTrigger = { [weak self] trigger in
            self?.handleTrigger(trigger)
        }
        hotkey.start()

        // Pipe recorder state into HUD model.
        elapsedSubscription = recorder.$elapsed
            .sink { [weak self] e in self?.hud.model.elapsed = e }
        levelSubscription = recorder.$levelRMS
            .sink { [weak self] l in self?.hud.model.level = l }
    }

    /// Programmatic equivalent of pressing the toggle hotkey (used by menu bar).
    func handleToggleFromMenu() {
        handleTrigger(.toggle)
    }

    /// Constructs the STT provider configured in Settings, falling back to whichever provider
    /// has a key available if the configured one is missing. Order: configured → groq → whisper → gemini.
    private func makeSTT() throws -> STTProvider {
        let configured = settings.sttProvider
        if let provider = tryProvider(configured) { return provider }

        for fallback in [STTProviderKind.groq, .whisper, .gemini] where fallback != configured {
            if let provider = tryProvider(fallback) {
                Log.stt.info("STT auto-fallback: \(configured.rawValue) key missing → using \(fallback.rawValue)")
                return provider
            }
        }

        // Nothing configured at all.
        switch configured {
        case .groq:    throw GroqWhisperSTT.GroqSTTError.missingKey
        case .whisper: throw WhisperClient.WhisperError.missingKey
        case .gemini:  throw GeminiSTT.GeminiSTTError.missingKey
        }
    }

    private func tryProvider(_ kind: STTProviderKind) -> STTProvider? {
        switch kind {
        case .groq:
            guard let key = keychain.get(.groq) else { return nil }
            return GroqWhisperSTT(apiKey: key)
        case .whisper:
            guard let key = keychain.get(.openai) else { return nil }
            return WhisperClient(apiKey: key)
        case .gemini:
            guard let key = keychain.get(.google) else { return nil }
            return GeminiSTT(apiKey: key)
        }
    }

    /// Returns a non-HTTP, app-specific actionable hint for known error types.
    private static func customHint(for error: Error) -> String? {
        if let e = error as? TextInjector.DeliveryError {
            switch e {
            case .accessibilityNotGranted:
                return "Settings → Permissions → Reset Accessibility"
            }
        }
        return nil
    }

    /// Pulls the HTTP status code out of any of our provider error types so we can
    /// surface a contextual hint in the HUD.
    private static func extractHTTPStatus(from error: Error) -> Int? {
        if let e = error as? WhisperClient.WhisperError, case .http(let c, _) = e { return c }
        if let e = error as? GroqWhisperSTT.GroqSTTError, case .http(let c, _) = e { return c }
        if let e = error as? GeminiSTT.GeminiSTTError, case .http(let c, _) = e { return c }
        if let e = error as? LLMError, case .http(let c, _) = e { return c }
        return nil
    }

    /// Set the mode to use for the *next* dictation only.
    func selectNextMode(_ modeId: String) {
        nextModeId = modeId
        if let m = modes.mode(id: modeId) {
            hud.model.modeName = "Next: " + m.name
            hud.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                if case .idle = self.state { self.hud.hide() }
            }
        }
    }

    private func handleTrigger(_ trigger: HotkeyManager.Trigger) {
        switch trigger {
        case .toggle:
            // Carbon ⌥⌘Space — same semantics as a tap.
            handleTap()
        case .tap:
            handleTap()
        case .escape:
            // Esc behaves the same as a tap of the configured key: stop + run pipeline.
            handleTap()
        case .holdStart:
            if case .idle = state { beginRecording(trigger: .hold) }
        case .holdEnd:
            // Only end recording if we're currently in a HOLD-mode session.
            // Toggle-mode recordings ignore key release — they end only on tap/Esc.
            if case .recording(_, .hold) = state {
                endRecording()
            }
        }
    }

    /// Tap (or toggle hotkey, or Esc) — flips the toggle.
    private func handleTap() {
        switch state {
        case .idle:
            beginRecording(trigger: .toggle)
        case .recording:
            endRecording()
        case .processing:
            break
        }
    }

    private func beginRecording(trigger: RecordingTrigger) {
        let modeId = nextModeId ?? settings.defaultModeId
        nextModeId = nil
        let mode = modes.mode(id: modeId) ?? modes.modes.first ?? DefaultModes.all[0]
        hud.model.modeName = mode.name
        hud.model.recordingTrigger = trigger
        hud.model.phase = .recording
        hud.model.elapsed = 0
        hud.model.level = 0
        hud.show()

        Log.app.info("▶︎ beginRecording trigger=\(String(describing: trigger)) mode=\(mode.name)")
        do {
            try recorder.start()
            state = .recording(modeId: mode.id, trigger: trigger)
            hotkey.setEscapeCaptureActive(true)
            playSound(.start)
        } catch {
            Log.app.error("recorder.start failed: \(error.localizedDescription)")
            showError(error)
        }
    }

    private func endRecording() {
        guard case .recording(let modeId, _) = state else { return }
        state = .processing
        hud.model.phase = .transcribing
        hotkey.setEscapeCaptureActive(false)
        playSound(.stop)

        do {
            let wav = try recorder.stop()
            Log.app.info("⏹ recording stopped, captured \(wav.count) bytes WAV")
            Task { await self.runPipeline(wav: wav, modeId: modeId) }
        } catch {
            Log.app.error("recorder.stop failed: \(error.localizedDescription)")
            showError(error)
            state = .idle
        }
    }

    private func cancelRecording() {
        recorder.cancel()
        state = .idle
        hotkey.setEscapeCaptureActive(false)
        hud.hide()
    }

    private func runPipeline(wav: Data, modeId: String) async {
        let mode = modes.mode(id: modeId) ?? DefaultModes.all[0]

        let stt: STTProvider
        do {
            stt = try makeSTT()
        } catch {
            Log.stt.error("STT init failed: \(error.localizedDescription)")
            showError(error)
            state = .idle
            return
        }

        let langHint = settings.audioLanguage.whisperCode
        Log.stt.info("→ STT (\(self.settings.sttProvider.rawValue)): uploading \(wav.count) bytes lang=\(langHint ?? "auto")")
        let transcript: TranscriptionResult
        do {
            transcript = try await stt.transcribe(
                wav: wav,
                biasPrompt: glossary.whisperBiasPrompt(),
                language: langHint
            )
        } catch {
            Log.stt.error("STT failed: \(error.localizedDescription)")
            showError(error)
            state = .idle
            return
        }

        Log.stt.info("← STT: lang=\(transcript.language) dur=\(transcript.durationMs)ms text=\"\(transcript.text)\"")
        hud.model.language = transcript.language

        // Step 2: post-process via selected LLM mode.
        hud.model.phase = .processing(modeName: mode.name)
        let processor = PostProcessor(
            mode: mode,
            language: transcript.language,
            glossary: glossary.llmGlossaryBlock(),
            koreanTone: settings.koreanTone
        )

        let final: String
        do {
            Log.llm.info("→ Post-process via \(mode.provider.rawValue) (\(mode.model))")
            final = try await processor.run(transcript: transcript.text)
            Log.llm.info("← Post-process out: \"\(final)\"")
        } catch {
            Log.llm.error("Post-process failed: \(error.localizedDescription)")
            showError(error)
            state = .idle
            return
        }

        guard !final.isEmpty else {
            Log.app.error("Pipeline produced empty text — nothing to paste")
            showError(NSError(domain: "K-Whisper", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Empty result — nothing to paste."
            ]))
            state = .idle
            return
        }

        // Step 3: deliver. If Accessibility isn't granted the keystrokes are silently
        // swallowed — we MUST surface that as an error rather than show a fake "✓ Inserted".
        Log.inject.info("→ Delivering \(final.count) chars via \(self.settings.outputMethod.rawValue)")
        do {
            try TextInjector.deliver(final)
        } catch {
            Log.inject.error("Delivery failed: \(error.localizedDescription)")
            showError(error)
            state = .idle
            return
        }

        // Step 4: history + brief success indicator.
        history.add(HistoryEntry(
            modeId: mode.id,
            modeName: mode.name,
            language: transcript.language,
            durationMs: transcript.durationMs,
            rawTranscript: transcript.text,
            processedText: final
        ))

        hud.model.phase = .delivered
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            if case .idle = self.state {
                self.hud.model.phase = .idle
                self.hud.hide()
            }
        }
        state = .idle
    }

    private func showError(_ error: Error) {
        Log.app.error("✗ \(error.localizedDescription)")
        let status = Self.extractHTTPStatus(from: error)
        let hint = Self.customHint(for: error)
            ?? status.flatMap { APIErrorParser.hint(status: $0) }
            ?? "See Console.app · filter app.kwhisper"
        hud.model.phase = .error(message: error.localizedDescription, hint: hint)
        hud.show()
        // Persist error 10s so user has time to read it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self else { return }
            if case .idle = self.state { self.hud.hide() }
            self.hud.model.phase = .idle
        }
    }

    private enum SoundKind { case start, stop }
    private func playSound(_ kind: SoundKind) {
        guard settings.playSounds else { return }
        let name: String
        switch kind {
        case .start: name = "Tink"
        case .stop:  name = "Pop"
        }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
