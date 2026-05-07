# STT-KR (Voxa)

A native macOS dictation app focused on **Korean + English** with high accuracy and sub-second latency. Hold a key, speak, and your transcribed text appears at the cursor — with optional LLM post-processing for cleanup, translation, or reformatting.

Built as a personal alternative to Superwhisper, using your own API keys.

## Features

- **Push-to-talk** via right-Command (no Input Monitoring permission needed) — 150 ms activation delay so quick chord like `right-Cmd+Backspace` still works system-wide
- **Toggle hotkey** `⌥⌘Space` as alternative
- **Korean + English** with auto-detection and code-switching support
- **Per-mode LLM routing** — each mode picks its own provider/model
- Built-in modes: Default cleanup, Email, Slack, Korean → English, English → Korean, Code comment, Raw
- **Glossary** for proper nouns / project terms (biases STT and LLM cleanup)
- **Floating HUD pill** with live waveform, elapsed time, and current mode
- **Searchable history** of all dictations
- **API keys stored locally** in `~/Library/Application Support/Voxa/secrets.json` (0600 permissions, never sent anywhere except the provider's API)
- Native AppKit + SwiftUI; menu bar app, Dock icon shows only when Settings is open

## Speed

Target: **~400–800 ms end-to-end** on a warm pipeline.

| Stage | Cost |
|---|---|
| Groq STT (`whisper-large-v3-turbo`) | 200–500 ms |
| Groq LLM cleanup (`llama-3.1-8b-instant`) | 100–250 ms |
| Clipboard paste (with 80 ms restore delay) | ~80 ms |

## Build & run

```bash
cd stt-kr
./build.sh                    # produces build/Voxa.app
open build/Voxa.app           # right-click → Open the first time (unsigned)
```

To open in Xcode for development: `xed Package.swift` (or File → Open → select `Package.swift`).

## First-run setup

1. Approve permissions when prompted (Microphone + Accessibility). Speech-to-text and clipboard paste both need these.
2. Open **Settings → API Keys** and paste your **Groq** key (free at [console.groq.com/keys](https://console.groq.com/keys)). OpenAI / Anthropic / Google keys are optional alternatives.
3. Optional: **Settings → Glossary** — add proper nouns and project terms; they bias both STT and LLM cleanup.
4. Press **right-Command** (hold to dictate) or **⌥⌘Space** (toggle).

## Architecture

```
[right-Cmd hold]
    ↓
[AVAudioRecorder] → 16 kHz mono Int16 WAV
    ↓
[Groq Whisper Large-v3-Turbo] → text + detected language
    ↓
[Groq Llama 3.1 8B Instant] cleanup mode (or per-mode router)
    ↓
[Clipboard paste at cursor]   (saves + restores prior clipboard)
```

## Project layout

```
stt-kr/
├── Package.swift                  SPM executable target, no external deps
├── build.sh                       Builds + ad-hoc-signs Voxa.app, embeds AppIcon.icns
├── Resources/
│   ├── Info.plist
│   └── Voxa.entitlements
└── Sources/Voxa/
    ├── App/                       main, AppDelegate, MenuBarController, MainMenu, AppIconFactory
    ├── Audio/                     AudioRecorder (AVAudioRecorder), WAVEncoder
    ├── Hotkey/                    Carbon toggle + NSEvent flag-changed hold monitor
    ├── Transcription/             STTProvider, GroqWhisperSTT, WhisperClient, GeminiSTT
    ├── PostProcessing/            LLMProvider, GroqProvider, ClaudeProvider, OpenAIProvider, GeminiProvider, PostProcessor
    ├── Output/                    TextInjector (clipboard paste + synthetic typing)
    ├── Modes/                     Mode model + ModeManager + DefaultModes
    ├── Storage/                   Settings, SecretsStore (file-backed), History, Glossary
    ├── Permissions/               PermissionManager + Diagnostics (test buttons)
    ├── UI/                        Settings tabs + floating HUD pill
    ├── Coordinator/               DictationCoordinator (wires everything)
    └── Util/                      Logger, Networking (HTTP/2 keep-alive + prewarm)
```

## License

Personal use. No license granted for redistribution.
