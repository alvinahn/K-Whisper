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
                Text("Keys are stored at \(SecretsStore.shared.storagePath) with owner-only (0600) permissions. They never leave this Mac except in API requests to the respective providers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Groq (recommended for STT)") {
                keyField(
                    title: "API key (gsk_...)",
                    text: $groqKey,
                    isSet: keychain.hasGroq,
                    save: { try keychain.set(.groq, value: groqKey) },
                    clear: { keychain.clear(.groq); groqKey = "" }
                )
                Text("Used for: Whisper Large-v3-Turbo STT — fastest cloud option, ~$0.04/hr (~10× cheaper than OpenAI Whisper). Get a free key at console.groq.com/keys.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("OpenAI") {
                keyField(
                    title: "API key (sk-...)",
                    text: $openaiKey,
                    isSet: keychain.hasOpenAI,
                    save: { try keychain.set(.openai, value: openaiKey) },
                    clear: { keychain.clear(.openai); openaiKey = "" }
                )
                Text("Used for: whisper-1 STT (older, slower) + GPT post-processing modes.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Anthropic (Claude)") {
                keyField(
                    title: "API key (sk-ant-...)",
                    text: $anthropicKey,
                    isSet: keychain.hasAnthropic,
                    save: { try keychain.set(.anthropic, value: anthropicKey) },
                    clear: { keychain.clear(.anthropic); anthropicKey = "" }
                )
                Text("Used for: Claude post-processing modes (e.g. Email, KO↔EN translation).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Google (Gemini)") {
                keyField(
                    title: "API key",
                    text: $googleKey,
                    isSet: keychain.hasGoogle,
                    save: { try keychain.set(.google, value: googleKey) },
                    clear: { keychain.clear(.google); googleKey = "" }
                )
                Text("Used for: Gemini post-processing modes (default cleanup, code comment).")
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
            Button("Save") {
                do {
                    try save()
                    statusMessage = "Saved."
                } catch {
                    statusMessage = "Save failed: \(error.localizedDescription)"
                }
            }
            .disabled(text.wrappedValue.isEmpty)
            Button("Clear") { clear(); statusMessage = "Cleared." }
                .disabled(!isSet)
        }
    }
}
