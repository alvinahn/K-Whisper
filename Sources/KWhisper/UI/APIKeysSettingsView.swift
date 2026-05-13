import SwiftUI

struct APIKeysSettingsView: View {
    @ObservedObject private var keychain = SecretsStore.shared

    @State private var openaiKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var googleKey: String = ""
    @State private var groqKey: String = ""
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section {
                Text("API 키는 \(SecretsStore.shared.storagePath)에 저장됩니다. 이 Mac 밖으로는 각 서비스 요청에만 전송됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Groq (음성 인식 추천)") {
                keyField(
                    title: "API 키 (gsk_...)",
                    text: $groqKey,
                    isSet: keychain.hasGroq,
                    save: { try keychain.set(.groq, value: groqKey) },
                    clear: { keychain.clear(.groq); groqKey = "" }
                )
                Text("용도: Whisper Large-v3-Turbo 음성 인식. 클라우드 옵션 중 가장 빠른 편입니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("OpenAI") {
                keyField(
                    title: "API 키 (sk-...)",
                    text: $openaiKey,
                    isSet: keychain.hasOpenAI,
                    save: { try keychain.set(.openai, value: openaiKey) },
                    clear: { keychain.clear(.openai); openaiKey = "" }
                )
                Text("용도: whisper-1 음성 인식과 GPT 기반 AI 처리.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Anthropic (Claude)") {
                keyField(
                    title: "API 키 (sk-ant-...)",
                    text: $anthropicKey,
                    isSet: keychain.hasAnthropic,
                    save: { try keychain.set(.anthropic, value: anthropicKey) },
                    clear: { keychain.clear(.anthropic); anthropicKey = "" }
                )
                Text("용도: Claude 기반 AI 처리.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Google (Gemini)") {
                keyField(
                    title: "API 키",
                    text: $googleKey,
                    isSet: keychain.hasGoogle,
                    save: { try keychain.set(.google, value: googleKey) },
                    clear: { keychain.clear(.google); googleKey = "" }
                )
                Text("용도: Gemini 음성 인식과 AI 처리.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let msg = statusMessage {
                Text(msg).font(.caption).foregroundStyle(.green)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func keyField(
        title: String,
        text: Binding<String>,
        isSet: Bool,
        save: @escaping () throws -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        HStack {
            SecureField(title, text: text)
                .textFieldStyle(.roundedBorder)
            if isSet {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            Button("저장") {
                do {
                    try save()
                    statusMessage = "저장했습니다."
                } catch {
                    statusMessage = "저장 실패: \(error.localizedDescription)"
                }
            }
            .disabled(text.wrappedValue.isEmpty)
            Button("삭제") { clear(); statusMessage = "삭제했습니다." }
                .disabled(!isSet)
        }
    }
}
