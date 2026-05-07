import SwiftUI
import Carbon.HIToolbox

struct GeneralSettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var modes = ModeManager.shared

    var body: some View {
        Form {
            Section("Speech-to-text") {
                Picker("STT provider", selection: $settings.sttProvider) {
                    ForEach(STTProviderKind.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                Text(sttHint)
                    .font(.caption).foregroundStyle(.secondary)

                Picker("Audio language", selection: $settings.audioLanguage) {
                    ForEach(AudioLanguage.allCases) { l in
                        Text(l.displayName).tag(l)
                    }
                }
                Text("Forcing the language (vs auto-detect) reduces Korean transcription errors when audio is mostly Korean.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Default mode") {
                Picker("When you trigger dictation", selection: $settings.defaultModeId) {
                    ForEach(modes.modes) { mode in
                        Text(mode.name).tag(mode.id)
                    }
                }
            }

            Section("Output") {
                Picker("Insert text via", selection: $settings.outputMethod) {
                    ForEach(OutputMethod.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                Toggle("Play start/stop sounds", isOn: $settings.playSounds)
            }

            Section("Triggers") {
                Toggle("Enable push-to-talk (hold a key to dictate)", isOn: $settings.holdKeyEnabled)
                if settings.holdKeyEnabled {
                    Picker("Hold key", selection: $settings.holdKey) {
                        ForEach(HoldKey.allCases) { k in
                            Text(k.displayName).tag(k)
                        }
                    }
                    Text("Right ⌘ doesn't require Input Monitoring permission. Fn does.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Toggle hotkey")
                    Spacer()
                    Text(hotkeyDisplay).foregroundStyle(.secondary).font(.system(.body, design: .monospaced))
                }
                Text("Default ⌥⌘Space. Customize in code (Settings.swift) for now — full hotkey recorder UI coming soon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Korean") {
                Picker("Default tone for translation", selection: $settings.koreanTone) {
                    ForEach(KoreanTone.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var sttHint: String {
        switch settings.sttProvider {
        case .groq:    return "Uses your Groq key. Whisper Large-v3-Turbo at ~200–500ms. Best Korean accuracy. ~$0.04/hr — ~10× cheaper than OpenAI Whisper. Free tier available."
        case .whisper: return "Uses your OpenAI key. whisper-1 (older v2-era model). $0.006/min. Decent English, weaker Korean than Groq."
        case .gemini:  return "Uses your Google (Gemini) key. Free tier covers personal use. Decent Korean."
        }
    }

    private var hotkeyDisplay: String {
        let kc = settings.toggleHotkeyKeyCode
        let mods = settings.toggleHotkeyModifiers
        var parts: [String] = []
        if mods & (1 << 12) != 0 { parts.append("⌃") } // controlKey
        if mods & (1 << 11) != 0 { parts.append("⌥") } // optionKey
        if mods & (1 << 9)  != 0 { parts.append("⇧") } // shiftKey
        if mods & (1 << 8)  != 0 { parts.append("⌘") } // cmdKey
        parts.append(keyName(for: kc))
        return parts.joined()
    }

    private func keyName(for kc: Int) -> String {
        switch kc {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Escape: return "Esc"
        default: return "key\(kc)"
        }
    }
}
