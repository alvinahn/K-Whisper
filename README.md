# K-Whisper

A native macOS dictation app focused on **Korean + English** with high accuracy and sub-second latency. Hold a key, speak, and your transcribed text appears at the cursor — with optional LLM post-processing for cleanup, translation, or reformatting.

Built as a personal alternative to Superwhisper, using your own API keys.

## Features

### Dictation
- **Hold-to-talk** by holding **Right ⌥ Option** (default; configurable to Right ⌘, Right ⇧, Right ⌃, or Fn). Recording while held; release to send.
- **Tap-to-toggle** by quick-tapping the same key. Recording continues until you tap again or press **Esc**. Esc behaves identically to a toggle-off — never discards.
- **150 ms activation delay** so chords like `Right-Opt + 1` (`¡`) or `Right-Cmd + Backspace` still work system-wide.
- Toggle hotkey **⌥⌘Space** as an alternative way to start/stop.
- Uses only **Microphone + Accessibility** permissions (no Input Monitoring required).

### Languages
- **Korean + English** with auto-detection and code-switching support.
- Optional **Audio language hint** picker forces Whisper to a specific language for higher accuracy on known-Korean recordings.
- **Glossary** for proper nouns / project terms (biases STT and LLM cleanup).

### Pipeline
- **STT default**: Groq Whisper Large-v3-Turbo (~$0.04/hr, ~10× cheaper than OpenAI Whisper, much better Korean than `whisper-1`).
- **LLM cleanup default**: Groq Llama 3.3 70B Versatile with Korean-aware prompt that catches verb-merge errors (e.g. `미치고 버렸네` → `미쳐버렸네`).
- **Per-mode LLM routing** — each mode picks its own provider/model.
- Built-in modes: Default cleanup, Email, Slack, Korean → English, English → Korean, Code comment, Raw.

### UX
- **Floating HUD pill** centered on screen with particle waveform that animates from real audio level while recording and a synthetic "thinking" pulse during transcribing/processing.
- **Settings window** with native macOS sidebar navigation and 6 sections (General, API Keys, Modes, Glossary, History, Permissions).
- **Searchable history** of all dictations with relative timestamps.
- **API keys stored locally** in `~/Library/Application Support/KWhisper/secrets.json` (0600 permissions, never sent anywhere except the provider's API).
- Native AppKit + SwiftUI; menu bar app, Dock icon shows only when Settings is open.

## Speed

Target: **~400–800 ms end-to-end** on a warm pipeline.

| Stage | Cost |
|---|---|
| Groq STT (`whisper-large-v3-turbo`) | 200–500 ms |
| Groq LLM cleanup (`llama-3.3-70b-versatile`, Korean-aware) | 200–400 ms |
| Clipboard paste (with 80 ms restore delay) | ~80 ms |

Pipeline pre-warms HTTP/2 TLS to api.groq.com / api.anthropic.com / api.openai.com / generativelanguage.googleapis.com on launch so the first dictation is just as fast as subsequent ones.

## Build & run

```bash
cd k-whisper
./build.sh                    # produces build/K-Whisper.app
open build/K-Whisper.app      # right-click → Open the first time (unsigned)
```

To open in Xcode for development: `xed Package.swift`.

## DMG distribution

```bash
./make-dmg.sh                 # produces build/K-Whisper-{version}.dmg
```

The DMG opens with the standard "drag K-Whisper onto Applications" installer layout — title, subtitle, arrow, brand background, and the real Applications folder icon.

## First-run setup

1. Approve permissions when prompted (Microphone + Accessibility).
2. Open **Settings → API Keys** and paste your **Groq** key (free at [console.groq.com/keys](https://console.groq.com/keys)). OpenAI / Anthropic / Google keys are optional alternatives.
3. Optional: **Settings → Glossary** — add proper nouns and project terms.
4. Hold **Right ⌥ Option** and speak.

If paste stops working after a rebuild (ad-hoc signatures invalidate Accessibility grants), open **Settings → Permissions → Reset & re-grant**. It runs `tccutil reset Accessibility app.kwhisper` and re-prompts so the new code-signature is registered cleanly — no manual `−` / `+` dance.

## Architecture

```
[Right-⌥ hold OR tap]
    ↓
[AVAudioRecorder] → 16 kHz mono Int16 WAV
    ↓
[Groq Whisper Large-v3-Turbo] → text + detected language
    ↓
[Groq Llama 3.3 70B Versatile] cleanup mode (per-mode router)
    ↓
[Clipboard paste at cursor]   (saves + restores prior clipboard)
```

## Project layout

```
k-whisper/
├── Package.swift                  SPM executable target, no external deps
├── build.sh                       Builds + ad-hoc-signs K-Whisper.app, embeds AppIcon.icns
├── make-dmg.sh                    Packages K-Whisper.app into a distributable DMG
├── Resources/
│   ├── Info.plist
│   └── KWhisper.entitlements
└── Sources/KWhisper/
    ├── App/                       main, AppDelegate, MenuBarController, MainMenu, AppIconFactory
    ├── Audio/                     AudioRecorder (AVAudioRecorder), WAVEncoder
    ├── Hotkey/                    Carbon toggle + NSEvent flag-changed hold/tap monitor
    ├── Transcription/             STTProvider, GroqWhisperSTT, WhisperClient, GeminiSTT
    ├── PostProcessing/            LLMProvider, GroqProvider, ClaudeProvider, OpenAIProvider, GeminiProvider, PostProcessor
    ├── Output/                    TextInjector (clipboard paste + dedup safety net)
    ├── Modes/                     Mode model + ModeManager + DefaultModes
    ├── Storage/                   Settings, SecretsStore (file-backed), History, Glossary
    ├── Permissions/               PermissionManager (incl. tccutil reset) + Diagnostics
    ├── UI/                        NavigationSplitView Settings + floating HUD pill (particles)
    ├── Coordinator/               DictationCoordinator (wires everything)
    └── Util/                      Logger, Networking (HTTP/2 keep-alive + prewarm), APIErrorParser, DataMigration
```

## License

Personal use. No license granted for redistribution.
