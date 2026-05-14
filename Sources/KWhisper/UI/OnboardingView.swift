import SwiftUI
import AppKit

struct OnboardingView: View {
    @ObservedObject private var secrets = SecretsStore.shared
    @ObservedObject private var perms = PermissionManager.shared
    @ObservedObject private var diag = Diagnostics.shared
    @ObservedObject private var settings = Settings.shared

    @State private var groqKey = ""
    @State private var saveMessage: String?

    private var setupComplete: Bool {
        secrets.hasGroq && perms.hasMicrophone && perms.hasAccessibility
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: setupComplete ? "checkmark.seal.fill" : "waveform.badge.mic")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(setupComplete ? .green : .accentColor)
                            .frame(width: 42)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("K-Whisper 시작하기")
                                .font(.title2.weight(.semibold))
                            Text("한국어와 영어로 말하면 텍스트로 바꿔 원하는 앱에 바로 붙여넣습니다.")
                                .foregroundStyle(.secondary)
                            Text(setupComplete ? "기본 설정이 완료되었습니다." : "Groq API 키와 macOS 권한만 준비하면 바로 사용할 수 있습니다.")
                                .font(.caption)
                                .foregroundStyle(setupComplete ? .green : .secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("1. Groq API 키") {
                setupRow(
                    title: "Groq 키",
                    state: secrets.hasGroq ? .done : .pending,
                    detail: "빠른 한국어/영어 음성 인식을 위해 Whisper Large-v3-Turbo를 사용합니다."
                )

                HStack(spacing: 8) {
                    SecureField("gsk_...", text: $groqKey)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                    Button {
                        saveGroqKey(testAfterSave: true)
                    } label: {
                        Label("저장하고 테스트", systemImage: "checkmark.circle")
                    }
                    .disabled(groqKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        openURL("https://console.groq.com/keys")
                    } label: {
                        Label("키 만들기", systemImage: "arrow.up.right.square")
                    }
                }

                Text("Groq 계정에서 API 키를 만든 뒤 여기에 붙여넣으세요. 키는 \(secrets.storagePath)에 0600 권한으로 저장됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Button {
                        openURL("https://console.groq.com/docs/rate-limits")
                    } label: {
                        Label("무료 한도 보기", systemImage: "chart.bar.doc.horizontal")
                    }
                    Button {
                        openURL("https://groq.com/pricing")
                    } label: {
                        Label("요금 보기", systemImage: "dollarsign.circle")
                    }
                }

                Text("개인 받아쓰기 용도는 무료 플랜으로 충분한 경우가 많습니다. 무료 플랜은 월 정액 한도보다 요청/오디오 시간 제한 방식이고, 유료 사용도 Whisper Large-v3-Turbo 기준 오디오 1시간당 $0.04 수준입니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(saveMessage.hasPrefix("저장") ? .green : .red)
                }
            }

            Section("2. macOS 권한") {
                setupRow(
                    title: "마이크",
                    state: perms.hasMicrophone ? .done : .pending,
                    detail: "말한 내용을 녹음하기 위해 필요합니다."
                ) {
                    Button("허용 요청") {
                        Task { _ = await perms.requestMicrophone() }
                    }
                    Button("시스템 설정") {
                        perms.openMicrophonePane()
                    }
                }

                setupRow(
                    title: "접근성",
                    state: perms.hasAccessibility ? .done : .pending,
                    detail: "변환된 텍스트를 현재 앱에 붙여넣기 위해 필요합니다."
                ) {
                    Button("다시 허용") {
                        perms.resetAccessibility()
                    }
                    Button("시스템 설정") {
                        perms.openAccessibilityPane()
                    }
                }

                Text("재빌드 후 붙여넣기나 단축키가 이상하면 접근성의 **다시 허용**을 누른 뒤 시스템 설정에서 K-Whisper를 켜주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("3. 테스트") {
                setupRow(
                    title: "마이크 테스트",
                    state: diag.micTestPeak > 0.01 ? .done : .pending,
                    detail: "레벨 미터가 움직이면 입력 장치가 정상입니다."
                ) {
                    Button(diag.micTestActive ? "중지" : "시작") {
                        diag.toggleMicTest()
                    }
                }

                if diag.micTestActive {
                    MicLevelMeter(
                        level: diag.micTestLevel,
                        peak: diag.micTestPeak,
                        seconds: diag.micTestSeconds
                    )
                }

                setupRow(
                    title: "붙여넣기 테스트",
                    state: diag.pasteTestSucceeded ? .done : .pending,
                    detail: "텍스트 입력 칸에 커서를 둔 뒤 테스트하면 3초 후 샘플 문구를 붙여넣습니다."
                ) {
                    Button("테스트") {
                        diag.testPaste()
                    }
                }

                if !diag.lastMessage.isEmpty {
                    Text(diag.lastMessage)
                        .font(.caption)
                        .foregroundStyle(diag.lastSuccess ? .green : .secondary)
                        .textSelection(.enabled)
                }
            }

            Section("4. 사용 방법") {
                setupRow(
                    title: settings.holdKey.displayName,
                    state: .info,
                    detail: "길게 누르면 누르고 말하기, 짧게 탭하면 녹음 토글입니다. 기본 추천 키는 Right ⌥ Option입니다."
                )
                Text("메모장, 카카오톡, 브라우저 등 원하는 입력 칸을 클릭한 뒤 Right ⌥ Option을 누른 채 말해보세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func setupRow<Actions: View>(
        title: String,
        state: SetupState,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: state.systemImage)
                .foregroundStyle(state.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            actions()
        }
    }

    private func setupRow(
        title: String,
        state: SetupState,
        detail: String
    ) -> some View {
        setupRow(title: title, state: state, detail: detail) {
            EmptyView()
        }
    }

    private func saveGroqKey(testAfterSave: Bool) {
        do {
            try secrets.set(.groq, value: groqKey)
            saveMessage = "저장했습니다."
            if testAfterSave {
                diag.testGroqKey()
            }
        } catch {
            saveMessage = "저장 실패: \(error.localizedDescription)"
        }
    }

    private func openURL(_ raw: String) {
        guard let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }
}

private enum SetupState {
    case done
    case pending
    case info

    var systemImage: String {
        switch self {
        case .done: return "checkmark.circle.fill"
        case .pending: return "circle"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .done: return .green
        case .pending: return .secondary
        case .info: return .accentColor
        }
    }
}
