# CLAUDE.md

Project-specific instructions for Claude Code working on this repo.

## What this project is

A native macOS menu-bar dictation app, Korean+English-focused, modeled after Superwhisper. Owner: Alvin (alvinahn). Personal-use; not currently distributed.

App name: **K-Whisper** (display) / `KWhisper` (binary, Swift target, paths) / `app.kwhisper` (bundle identifier). The repo lives at `github.com/alvinahn/K-Whisper`.

## Build / run

```bash
./build.sh               # full pipeline: swift build + iconset → .icns + ad-hoc sign + assemble K-Whisper.app
open build/K-Whisper.app # launch the bundled app (NOT `swift run` — global hotkeys + perms only work as a real .app)

./make-dmg.sh            # packages K-Whisper.app into build/K-Whisper-{version}.dmg with installer layout
```

`./build.sh` outputs to `build/K-Whisper.app`. Each rebuild produces a new ad-hoc code signature, which **invalidates macOS Accessibility grants**. Direct the user to **Settings → Permissions → Reset & re-grant** — the in-app button runs `tccutil reset Accessibility app.kwhisper` and re-prompts, so they don't need the manual `−` / `+` dance in System Settings.

## Architecture quick reference

The dictation pipeline is sequential, top-to-bottom:

```
HoldKeyMonitor (NSEvent flag-changed) ──► HotkeyManager ──► DictationCoordinator
                                                                  │
                                                                  ├── AudioRecorder (AVAudioRecorder → 16kHz WAV)
                                                                  ├── STTProvider (GroqWhisperSTT default; Whisper / Gemini alternatives)
                                                                  ├── PostProcessor → LLMProvider (per-mode: GroqProvider default)
                                                                  └── TextInjector (clipboard paste; AX-checked, dedupe-protected)
```

`DictationCoordinator.runPipeline` (Sources/KWhisper/Coordinator/DictationCoordinator.swift) is the orchestration entry point. Trace there first.

The same hold key is BOTH push-to-talk AND a tap-to-toggle. `HoldKeyMonitor` emits `.tap` if released before the 150 ms activation threshold and `.holdStart` / `.holdEnd` after. `DictationCoordinator.handleTrigger` interprets — see `RecordingTrigger` enum (`.toggle` vs `.hold`) carried in `State.recording`. Esc is registered via Carbon hotkey only while recording is active and is treated identically to a tap.

## Critical conventions

- **Stay native.** No Electron, no Tauri, no third-party UI frameworks.
- **No new SPM dependencies** unless absolutely required. Package.swift has zero external deps and that's intentional. `SecretsStore` replaced KeychainAccess for this reason — every rebuild's new ad-hoc signature would re-prompt for Keychain access.
- **Storage**: API keys live in `~/Library/Application Support/KWhisper/secrets.json` with 0600 perms. `DataMigration.runIfNeeded()` (called first thing in AppDelegate) renames the legacy `Voxa/` folder to `KWhisper/` once if needed.
- **Logging**: use `Log.app/audio/hotkey/stt/llm/inject/ui` from `Util/Logger.swift`. The user views these via Console.app filtered to `subsystem == app.kwhisper`.
- **Permissions**: K-Whisper needs only Microphone + Accessibility. Avoid Input Monitoring (right-Opt / right-Cmd are normal modifiers — `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` works permission-free). Fn requires Input Monitoring; only used when user explicitly picks it.
- **Hold-to-talk has a 150 ms activation delay** so quick chords (right-Opt + 1 = `¡`, right-Cmd + Backspace, etc.) keep working system-wide. Don't shorten without understanding the trade-off.
- **Paste delay**: 80 ms clipboard restore. Don't lengthen.
- **TextInjector.deliver throws** if `AXIsProcessTrusted()` is false — surfaces a real error in HUD instead of fake "✓ Inserted".
- **dedupeExactDoubling** in TextInjector is a safety net for the rare case Llama 70B echoes its output ("X+X" with no separator). Don't remove it.
- **Settings UI uses NavigationSplitView**. Sidebar items are plain `Label(...).tag(tab)` inside `List(selection: $selection)`. **Do not wrap in `NavigationLink`** — that breaks selection-driven detail routing.
- **HotkeyManager subscriptions to Settings publishers must defer reload via `DispatchQueue.main.async`** — `@Published` fires in `willSet`, so the property hasn't committed yet at sink-time; reading `settings.holdKey` directly returns the stale value.
- **ModeEditor uses `.id(draft.id)`** so changing the selected mode resets `@State`. Without it the editor freezes on the first mode the user clicked.

## Defaults to remember

- **Hold key**: Right ⌥ Option (Superwhisper-style). Migration v2 forces this once for existing users.
- **Sounds**: OFF by default (migration v1).
- **STT provider**: Groq Whisper Large-v3 (full, not turbo — turbo strips Korean confirmation `?` and normalizes colloquial spellings like 같애 → 같아). Pipeline auto-falls-back to whichever provider key is present.
- **Default cleanup**: Groq `llama-3.3-70b-versatile` (NOT 8B — 70B handles Korean morphology far better).
- **Audio language hint**: auto-detect.
- **HUD position**: vertically + horizontally centered on screen.
- **Paste output**: clipboard paste (80 ms restore).
- **Settings auto-shows on every launch.**

## Speed targets

| Stage | Budget |
|---|---|
| STT | ≤500 ms |
| LLM cleanup | ≤400 ms (70B is slower than 8B but Korean-correct) |
| Paste | ≤100 ms |
| **End-to-end** | **≤1000 ms** |

If a change pushes any single stage over budget, flag it explicitly to the user.

## Korean accuracy rules of thumb

- Always pass Korean-or-mixed audio through `whisper-large-v3` (Groq) — full model, not turbo. The older OpenAI `whisper-1` API is **not acceptable** for Korean — it's the v2-era model with weak Korean.
- Default cleanup prompt explicitly catches verb-merge errors (e.g. `미치고 버렸네` → `미쳐버렸네`), particle confusion, compound endings.
- Glossary terms inject into BOTH the STT `prompt` field AND the LLM cleanup system prompt.
- Korean tone (반말/존댓말) is configurable in Settings → General. Translation modes interpolate `{KOREAN_TONE}` from the system prompt.
- LLM prompts for cleanup must say "EXACTLY ONCE" and forbid arrow notation. Llama 70B mimics teaching-by-example otherwise.

## DMG packaging notes (`make-dmg.sh`)

- Background image is rendered programmatically by the K-Whisper binary itself (`--render-dmg-background`).
- Applications shortcut: created post-mount as a real Finder alias via AppleScript (`make new alias file ...`), then has its icon force-set via `NSWorkspace.setIcon(_:forFile:)` (CLI flag `--copy-icon`). A plain `ln -s /Applications` shows up as an empty icon — don't use it.
- The DMG window background is currently rendered at 1× pixel density. Text is slightly soft on Retina; **multiple attempts to render at 2× have broken layout** (Finder's background-scaling behavior is more particular than expected). Don't try to "fix" Retina sharpness without verifying both 1× and Retina rendering work end-to-end.

## Things that are explicitly NOT in scope

- iOS / iPad version
- Real-time streaming transcription
- Local Whisper bundle (whisper.cpp / WhisperKit) — user has rejected the 1.6 GB download
- Apple `SpeechTranscriber` (macOS 26 native) — user tested Apple keyboard dictation and found Korean weak
- Speaker diarization / multi-mic
- Cloud sync / multi-device

## When making changes

- Run `./build.sh` after every change. **Don't** rely on `swift build` alone — bundle assembly + signing is part of the test loop.
- After non-trivial changes, remind the user to use **Settings → Permissions → Reset & re-grant** for Accessibility if paste or hotkeys behave oddly.
- Default modes live in `Sources/KWhisper/Modes/DefaultModes.swift`. `ModeManager.load()` always refreshes built-ins from code on launch (user-defined modes persist across launches).
- After visual / window-chrome changes, test all 6 Settings tabs to make sure NavigationSplitView selection still drives the detail column. Recently broken twice: NavigationLink-wrapped rows, and ModeEditor stale `@State`.

## Repo / contact

- GitHub: https://github.com/alvinahn/K-Whisper
- Owner email: dev@navio.im / admin@navio.im
- Branch: `main`
