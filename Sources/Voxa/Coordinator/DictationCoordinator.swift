import Foundation
import AppKit
import Combine

@MainActor
final class DictationCoordinator: ObservableObject {
    static let shared = DictationCoordinator()

    enum State: Equatable {
        case idle
        case recording(modeId: String)
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
            switch state {
            case .idle: beginRecording()
            case .recording: endRecording()
            case .processing: break
            }
        case .holdStart:
            if case .idle = state { beginRecording() }
        case .holdEnd(let durationMs):
            if durationMs < 200 {
                cancelRecording()
            } else if case .recording = state {
                endRecording()
            }
        }
    }

    private func beginRecording() {
        let modeId = nextModeId ?? settings.defaultModeId
        nextModeId = nil
        let mode = modes.mode(id: modeId) ?? modes.modes.first ?? DefaultModes.all[0]
        hud.model.modeName = mode.name
        hud.model.phase = .recording
        hud.model.elapsed = 0
        hud.model.level = 0
        hud.show()

        Log.app.info("▶︎ beginRecording mode=\(mode.name) provider=\(mode.provider.rawValue)")
        do {
            try recorder.start()
            state = .recording(modeId: mode.id)
            playSound(.start)
        } catch {
            Log.app.error("recorder.start failed: \(error.localizedDescription)")
            showError(error)
        }
    }

    private func endRecording() {
        guard case .recording(let modeId) = state else { return }
        state = .processing
        hud.model.phase = .transcribing
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
            showError(NSError(domain: "Voxa", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Empty result — nothing to paste."
            ]))
            state = .idle
            return
        }

        // Step 3: deliver.
        Log.inject.info("→ Delivering \(final.count) chars via \(self.settings.outputMethod.rawValue)")
        TextInjector.deliver(final)

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
        hud.model.phase = .error(error.localizedDescription)
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
