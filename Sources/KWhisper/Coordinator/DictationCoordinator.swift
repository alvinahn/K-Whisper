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
    private var pipelineTask: Task<Void, Never>?
    private var errorDismissWorkItem: DispatchWorkItem?
    private var errorActive: Bool = false

    /// Internal sentinel for "we tried to dictate but the user is offline." Surfaces
    /// as a clean error in the HUD instead of waiting for HTTP to time out.
    enum PipelineError: Error, LocalizedError {
        case offline
        var errorDescription: String? {
            switch self {
            case .offline: return "인터넷 연결 없음"
            }
        }
    }

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
        case .groq, .groqV3: throw GroqWhisperSTT.GroqSTTError.missingKey
        case .whisper:       throw WhisperClient.WhisperError.missingKey
        case .gemini:        throw GeminiSTT.GeminiSTTError.missingKey
        }
    }

    private func tryProvider(_ kind: STTProviderKind) -> STTProvider? {
        switch kind {
        case .groq:
            guard let key = keychain.get(.groq) else { return nil }
            return GroqWhisperSTT(apiKey: key)
        case .groqV3:
            guard let key = keychain.get(.groq) else { return nil }
            return GroqWhisperSTT(apiKey: key, model: "whisper-large-v3")
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
                return "설정 > 권한 > 접근성 다시 허용"
            }
        }
        return nil
    }

    /// Pulls HTTP error details out of provider errors so the HUD can show
    /// context-aware hints, especially Groq's TPM vs TPD rate-limit distinction.
    private static func extractHTTPError(from error: Error) -> (status: Int, body: String)? {
        if let e = error as? WhisperClient.WhisperError, case .http(let c, let b) = e { return (c, b) }
        if let e = error as? GroqWhisperSTT.GroqSTTError, case .http(let c, let b) = e { return (c, b) }
        if let e = error as? GeminiSTT.GeminiSTTError, case .http(let c, let b) = e { return (c, b) }
        if let e = error as? LLMError, case .http(let c, let b) = e { return (c, b) }
        return nil
    }

    /// Set the mode to use for the *next* dictation only.
    func selectNextMode(_ modeId: String) {
        nextModeId = modeId
        if let m = modes.mode(id: modeId) {
            hud.model.modeName = "입력 모드: " + m.name
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
            // Esc semantics depend on phase:
            //  - .recording: stop + run pipeline (same as a tap)
            //  - .processing: cancel the in-flight network calls
            //  - error HUD showing (state .idle): dismiss the error
            if errorActive { dismissError(); return }
            if case .processing = state { cancelProcessing(); return }
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
            if errorActive { dismissError() }
            beginRecording(trigger: .toggle)
        case .recording:
            endRecording()
        case .processing:
            // A second tap during processing = user wants out.
            cancelProcessing()
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
        // Keep Esc capture ON through .processing so the user can cancel a stuck
        // network call. We turn it off when the pipeline succeeds/fails/cancels.
        playSound(.stop)

        do {
            let wav = try recorder.stop()
            Log.app.info("⏹ recording stopped, captured \(wav.count) bytes WAV")
            pipelineTask = Task { [weak self] in
                await self?.runPipeline(wav: wav, modeId: modeId)
            }
        } catch {
            Log.app.error("recorder.stop failed: \(error.localizedDescription)")
            hotkey.setEscapeCaptureActive(false)
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

    /// User-initiated cancel while the network pipeline is running. Cancels the
    /// in-flight URLSession task (which throws `URLError.cancelled`), hides the HUD
    /// immediately, and returns to idle without flashing an error.
    private func cancelProcessing() {
        Log.app.info("✕ pipeline cancelled by user")
        pipelineTask?.cancel()
        pipelineTask = nil
        hotkey.setEscapeCaptureActive(false)
        state = .idle
        hud.model.phase = .idle
        hud.hide()
    }

    private func runPipeline(wav: Data, modeId: String) async {
        let pipelineStarted = Date()
        let mode = modes.mode(id: modeId) ?? DefaultModes.all[0]

        // Fail fast if NWPathMonitor says we're offline — avoids a 12s HTTP wait.
        if !NetworkReachability.shared.isOnline {
            Log.app.error("pipeline aborted: offline (NWPathMonitor)")
            failPipeline(with: PipelineError.offline)
            return
        }

        let stt: STTProvider
        do {
            stt = try makeSTT()
        } catch {
            Log.stt.error("STT init failed: \(error.localizedDescription)")
            failPipeline(with: error)
            return
        }

        let langHint = settings.audioLanguage.whisperCode
        Log.stt.info("→ STT (\(self.settings.sttProvider.rawValue)): uploading \(wav.count) bytes lang=\(langHint ?? "auto")")
        let transcript: TranscriptionResult
        let sttStarted = Date()
        do {
            transcript = try await stt.transcribe(
                wav: wav,
                biasPrompt: glossary.whisperBiasPrompt(),
                language: langHint
            )
        } catch {
            if Self.isUserCancel(error) {
                Log.stt.info("STT cancelled by user")
                return  // cancelProcessing already cleaned up
            }
            Log.stt.error("STT failed: \(error.localizedDescription)")
            failPipeline(with: error)
            return
        }

        let sttWallMs = Self.elapsedMs(since: sttStarted)
        Log.stt.info("← STT: lang=\(transcript.language) audioDur=\(transcript.durationMs)ms wall=\(sttWallMs)ms text=\"\(transcript.text)\"")
        hud.model.language = transcript.language

        // Step 1.5: deterministic glossary-alias substitution. STT mishearings of
        // known proper nouns (e.g. "션" → "셔니") get rewritten here, before the LLM
        // ever sees them.
        let correctedText = glossary.applySubstitutions(to: transcript.text)
        if correctedText != transcript.text {
            Log.stt.info("glossary subs: \"\(transcript.text)\" → \"\(correctedText)\"")
        }

        // Step 2: post-process via selected LLM mode.
        hud.model.phase = .processing(modeName: mode.name)
        let processor = PostProcessor(
            mode: mode,
            language: transcript.language,
            glossary: glossary.llmGlossaryBlock(),
            koreanTone: settings.koreanTone
        )

        let llmOutput: String
        let llmStarted = Date()
        do {
            Log.llm.info("→ Post-process via \(mode.provider.rawValue) (\(mode.model))")
            llmOutput = try await processor.run(transcript: correctedText)
            Log.llm.info("← Post-process wall=\(Self.elapsedMs(since: llmStarted))ms out=\"\(llmOutput)\"")
        } catch {
            if Self.isUserCancel(error) {
                Log.llm.info("Post-process cancelled by user")
                return
            }
            Log.llm.error("Post-process failed: \(error.localizedDescription)")
            failPipeline(with: error)
            return
        }

        // Step 2.5: deterministic punctuation restoration. Llama 70B occasionally
        // strips terminal `?`/`.`/`!` despite the explicit preserve rule. Restore
        // any that went missing, scoped to the conservative `cleanup` mode where the
        // LLM is supposed to be near-passthrough. Other modes (Email, Slack,
        // translation) intentionally rewrite, so we leave them alone. Verbatim mode
        // skips the LLM entirely so there's nothing to restore.
        let final: String
        if mode.id == "cleanup" {
            let restored = PunctuationRestorer.restore(input: correctedText, output: llmOutput)
            if restored != llmOutput {
                Log.llm.info("punctuation restored: \"\(llmOutput)\" → \"\(restored)\"")
            }
            final = restored
        } else {
            final = llmOutput
        }

        guard !final.isEmpty else {
            Log.app.error("Pipeline produced empty text — nothing to paste")
            failPipeline(with: NSError(domain: "K-Whisper", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "결과가 비어 있어 붙여넣을 내용이 없습니다."
            ]))
            return
        }

        // Step 3: deliver. If Accessibility isn't granted the keystrokes are silently
        // swallowed — we MUST surface that as an error rather than show a fake "✓ Inserted".
        Log.inject.info("→ Delivering \(final.count) chars via \(self.settings.outputMethod.rawValue)")
        let deliverStarted = Date()
        do {
            try TextInjector.deliver(final)
        } catch {
            Log.inject.error("Delivery failed: \(error.localizedDescription)")
            failPipeline(with: error)
            return
        }
        Log.inject.info("← Deliver wall=\(Self.elapsedMs(since: deliverStarted))ms")

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
        Log.app.info("✓ pipeline complete total=\(Self.elapsedMs(since: pipelineStarted))ms mode=\(mode.name)")
        pipelineTask = nil
        hotkey.setEscapeCaptureActive(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            if case .idle = self.state {
                self.hud.model.phase = .idle
                self.hud.hide()
            }
        }
        state = .idle
    }

    /// Returns true if `error` represents a user-initiated cancellation (either Swift
    /// concurrency cancellation or URLSession's `.cancelled` code). We never want to
    /// show an error HUD in that case — `cancelProcessing` has already cleaned up.
    private static func isUserCancel(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }

    private static func elapsedMs(since start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1000).rounded())
    }

    /// Unified failure path used by every catch in `runPipeline`: hides the spinner,
    /// resets state, drops Esc-cancel capture (showError will re-enable it for Esc-to-dismiss),
    /// and surfaces a contextual error in the HUD.
    private func failPipeline(with error: Error) {
        pipelineTask = nil
        hotkey.setEscapeCaptureActive(false)
        state = .idle
        showError(error)
    }

    private func showError(_ error: Error) {
        Log.app.error("✗ \(error.localizedDescription)")

        let title: String
        let hint: String

        if let urlErr = error as? URLError, let mapped = APIErrorParser.urlError(urlErr) {
            title = mapped.title
            hint = mapped.hint
        } else if case PipelineError.offline = error {
            title = "인터넷 연결 없음"
            hint = "Wi-Fi를 확인하세요 · Esc로 닫기"
        } else {
            let httpError = Self.extractHTTPError(from: error)
            title = error.localizedDescription
            hint = Self.customHint(for: error)
                ?? httpError.flatMap { APIErrorParser.hint(status: $0.status, body: $0.body) }
                ?? "Esc로 닫기 · Console.app 확인"
        }

        hud.model.phase = .error(message: title, hint: hint)
        hud.show()

        // Allow Esc to dismiss the error immediately rather than waiting 10s.
        errorActive = true
        hotkey.setEscapeCaptureActive(true)

        // Auto-dismiss after 10s so the HUD doesn't linger forever if the user walks away.
        errorDismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.dismissError()
        }
        errorDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0, execute: work)
    }

    /// Tears down the error HUD + Esc capture. Safe to call multiple times.
    private func dismissError() {
        errorDismissWorkItem?.cancel()
        errorDismissWorkItem = nil
        errorActive = false
        if case .idle = state {
            hotkey.setEscapeCaptureActive(false)
            hud.hide()
        }
        if case .error = hud.model.phase {
            hud.model.phase = .idle
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
