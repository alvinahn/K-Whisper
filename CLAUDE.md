# CLAUDE.md

Project-specific instructions for Claude Code working on this repo.

## What this project is

A native macOS menu-bar dictation app, Korean+English-focused, modeled after Superwhisper. Owner: Alvin (alvinahn). Personal-use; not currently distributed.

The user's name for the app internally is **Voxa**. The repo on GitHub is **STT-KR**. Use "Voxa" in code/UI strings; use "STT-KR" only when referring to the repo.

## Build / run

```bash
./build.sh           # full pipeline: swift build + iconset → .icns + ad-hoc sign + assemble Voxa.app
open build/Voxa.app  # launch the bundled app (NOT `swift run` — global hotkeys + perms only work as a real .app)
```

`./build.sh` outputs to `build/Voxa.app`. Each rebuild produces a new ad-hoc code signature, which **invalidates macOS Accessibility / Input-Monitoring grants**. Tell the user to re-grant Accessibility in System Settings after a rebuild if hotkeys or paste suddenly stop working.

The app is **unsigned** (no Apple Developer ID). First launch needs right-click → Open. macOS will eventually treat it as trusted for that bundle path, but each rebuild resets the grant.

## Architecture quick reference

The dictation pipeline is sequential, top-to-bottom:

```
HoldKeyMonitor (NSEvent flag-changed) ──► HotkeyManager ──► DictationCoordinator
                                                                  │
                                                                  ├── AudioRecorder (AVAudioRecorder → 16kHz WAV)
                                                                  ├── STTProvider (GroqWhisperSTT default; Whisper / Gemini alternatives)
                                                                  ├── PostProcessor → LLMProvider (per-mode: GroqProvider default)
                                                                  └── TextInjector (clipboard paste at cursor)
```

`DictationCoordinator.runPipeline` (Sources/Voxa/Coordinator/DictationCoordinator.swift) is the orchestration entry point. Trace there first.

## Critical conventions

- **Stay native.** No Electron, no Tauri, no third-party UI frameworks.
- **No new SPM dependencies** unless absolutely required. The current Package.swift has zero external deps and that's intentional. SecretsStore replaced KeychainAccess for this reason.
- **Storage**: API keys live in `~/Library/Application Support/Voxa/secrets.json` with 0600 perms. **Do not** revert to Keychain — every rebuild's new ad-hoc signature would re-prompt the user for keychain access.
- **Logging**: use `Log.app/audio/hotkey/stt/llm/inject/ui` from `Util/Logger.swift`. The user views these via Console.app filtered to `subsystem == im.navio.voxa`.
- **Permissions**: Voxa needs only Microphone + Accessibility. Avoid features that require Input Monitoring (right-Cmd / right-Opt are normal modifiers — they go through `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` which is permission-free).
- **Hold-to-talk has a 150 ms activation delay** so chords like `right-Cmd + Backspace` keep working system-wide. Don't shorten this without understanding the trade-off.
- **Paste delay**: 80 ms clipboard restore (was 250 ms). Don't lengthen.

## Speed targets

| Stage | Budget |
|---|---|
| STT | ≤500 ms |
| LLM cleanup | ≤250 ms |
| Paste | ≤100 ms |
| **End-to-end** | **≤900 ms** |

If a change pushes any single stage over budget, flag it explicitly to the user.

## Korean accuracy rules of thumb

- Always pass a Korean-or-mixed audio through `whisper-large-v3-turbo` (Groq) or better. The older `whisper-1` API is **not acceptable** for Korean — it's the v2-era model with weak Korean.
- Glossary terms are injected into the STT `prompt` field (Whisper bias) AND into the LLM cleanup system prompt. Don't drop either.
- Korean tone (반말/존댓말) is configurable in Settings → General. Translation modes interpolate `{KOREAN_TONE}` from the system prompt.

## Things that are explicitly NOT in scope

- iOS / iPad version
- Real-time streaming transcription
- Local Whisper bundle (whisper.cpp / WhisperKit) — user has rejected the 1.6 GB download
- Apple `SpeechTranscriber` (macOS 26 native) — user tested Apple keyboard dictation and found Korean weak
- Speaker diarization / multi-mic
- Cloud sync / multi-device

## When making changes

- Run `./build.sh` after every change. **Don't** rely on `swift build` alone — bundle assembly + signing is part of the test loop.
- After non-trivial changes, tell the user to **re-grant Accessibility** if paste or hotkeys behave oddly.
- Default modes live in `Sources/Voxa/Modes/DefaultModes.swift`. `ModeManager.load()` always refreshes built-ins from code on launch (user-defined modes persist across launches).

## Repo / contact

- GitHub: https://github.com/alvinahn/STT-KR
- Owner email: dev@navio.im / admin@navio.im
- Branch: `main`
