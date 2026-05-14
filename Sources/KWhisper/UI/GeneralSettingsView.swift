import SwiftUI
import Carbon.HIToolbox

struct GeneralSettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var modes = ModeManager.shared

    var body: some View {
        Form {
            Section("음성 인식") {
                Picker("음성 인식 서비스", selection: $settings.sttProvider) {
                    ForEach(STTProviderKind.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                Text(sttHint)
                    .font(.caption).foregroundStyle(.secondary)

                Picker("음성 언어", selection: $settings.audioLanguage) {
                    ForEach(AudioLanguage.allCases) { l in
                        Text(l.displayName).tag(l)
                    }
                }
                Text("대부분 한국어로 말한다면 언어를 고정하는 편이 한국어 인식 오류를 줄입니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("기본 입력 모드") {
                Picker("음성 입력 시", selection: $settings.defaultModeId) {
                    ForEach(modes.modes) { mode in
                        Text(mode.name).tag(mode.id)
                    }
                }
            }

            Section("출력") {
                Picker("텍스트 입력 방식", selection: $settings.outputMethod) {
                    ForEach(OutputMethod.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                Toggle("시작/종료 소리 재생", isOn: $settings.playSounds)
            }

            Section("단축키") {
                Toggle("누르고 말하기 사용", isOn: $settings.holdKeyEnabled)
                if settings.holdKeyEnabled {
                    Picker("누르고 말하기 키", selection: $settings.holdKey) {
                        ForEach(HoldKey.allCases) { k in
                            Text(k.displayName).tag(k)
                        }
                    }
                    Text("오른쪽 ⌥ Option을 추천합니다. Fn / Globe는 입력 모니터링 권한이 필요합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("토글 단축키")
                    Spacer()
                    Text(hotkeyDisplay).foregroundStyle(.secondary).font(.system(.body, design: .monospaced))
                }
                Text("기본값은 ⌥⌘Space입니다. 단축키 편집 UI는 추후 추가 예정입니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("한국어") {
                Picker("번역 기본 말투", selection: $settings.koreanTone) {
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
        case .groq:    return "Groq 키를 사용합니다. Whisper Large-v3-Turbo라 빠르고 한국어 정확도/속도 균형이 좋습니다."
        case .groqV3:  return "Groq 키를 사용합니다. Whisper Large-v3 전체 모델이라 조금 더 정확하지만 Turbo보다 느립니다."
        case .openAITranscribe: return "OpenAI 키를 사용합니다. GPT-4o Transcribe 모델입니다."
        case .openAIMiniTranscribe: return "OpenAI 키를 사용합니다. GPT-4o Mini Transcribe 모델입니다."
        case .whisper: return "OpenAI 키를 사용합니다. whisper-1은 영어는 무난하지만 한국어는 Groq보다 약합니다."
        case .gemini:  return "Google Gemini 키를 사용합니다. 개인 사용량은 무료 티어로 충분한 편입니다."
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
        case kVK_Space: return "스페이스"
        case kVK_Return: return "리턴"
        case kVK_Escape: return "Esc"
        default: return "키\(kc)"
        }
    }
}
