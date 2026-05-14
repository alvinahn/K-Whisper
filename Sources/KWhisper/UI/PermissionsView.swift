import SwiftUI

struct PermissionsView: View {
    @ObservedObject private var perms = PermissionManager.shared
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var diag = Diagnostics.shared

    var body: some View {
        Form {
            Section {
                Text("K-Whisper가 음성을 녹음하고 결과를 입력하려면 마이크와 접근성 권한이 필요합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            row(
                title: "마이크",
                granted: perms.hasMicrophone,
                why: "음성을 녹음하기 위해 필요합니다.",
                action: { Task { _ = await perms.requestMicrophone() } },
                actionLabel: "허용 요청",
                fallback: { perms.openMicrophonePane() }
            )

            Section("접근성") {
                HStack {
                    Image(systemName: perms.hasAccessibility ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(perms.hasAccessibility ? .green : .red)
                    Text(perms.hasAccessibility ? "허용됨" : "허용 안 됨")
                    Spacer()
                    Button("다시 허용") { perms.resetAccessibility() }
                        .help("기존 권한 항목을 지우고 현재 빌드의 K-Whisper.app로 다시 요청합니다.")
                    Button("시스템 설정 열기") { perms.openAccessibilityPane() }
                }
                Text("인식된 텍스트를 다른 앱에 입력할 때 필요합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                if !perms.hasAccessibility {
                    Text("**다시 허용**을 누른 뒤 시스템 설정의 손쉬운 사용 목록에서 K-Whisper를 켜주세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if settings.holdKeyEnabled && settings.holdKey == .fn {
                row(
                    title: "입력 모니터링 (Fn 키 전용)",
                    granted: nil,
                    why: "일반 탭에서 누르고 말하기 키를 오른쪽 ⌥ Option으로 바꾸면 이 권한은 필요 없습니다.",
                    action: nil,
                    actionLabel: nil,
                    fallback: { perms.openInputMonitoringPane() }
                )
            }

            Section("마이크 테스트") {
                HStack {
                    Button(diag.micTestActive ? "녹음 중지" : "녹음 시작") {
                        diag.toggleMicTest()
                    }
                    if diag.micTestActive {
                        MicLevelMeter(
                            level: diag.micTestLevel,
                            peak: diag.micTestPeak,
                            seconds: diag.micTestSeconds
                        )
                        .frame(maxWidth: 280)
                    }
                    Spacer()
                }
            }

            Section("진단") {
                HStack {
                    Button("붙여넣기 테스트") { diag.testPaste() }
                    Button("Groq 키 테스트") { diag.testGroqKey() }
                    Button("OpenAI 키 테스트") { diag.testOpenAIKey() }
                    Button("Google 키 테스트") { diag.testGoogleKey() }
                }
                HStack {
                    Button("Console.app에서 로그 열기") { diag.openConsole() }
                    Spacer()
                }
                if !diag.lastMessage.isEmpty {
                    Text(diag.lastMessage)
                        .foregroundStyle(diag.lastSuccess ? .green : .primary)
                        .font(.system(.body, design: .monospaced))
                        .padding(.top, 6)
                }
                Text("재빌드 후 입력이 실패하면 위 접근성 섹션에서 **다시 허용**을 누르세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func row(
        title: String,
        granted: Bool?,
        why: String,
        action: (() -> Void)?,
        actionLabel: String?,
        fallback: @escaping () -> Void
    ) -> some View {
        Section(title) {
            HStack {
                if let granted = granted {
                    Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(granted ? .green : .red)
                    Text(granted ? "허용됨" : "허용 안 됨")
                } else {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.gray)
                    Text("시스템 설정에서 확인")
                }
                Spacer()
                if let action = action, let label = actionLabel {
                    Button(label, action: action)
                }
                Button("시스템 설정 열기", action: fallback)
            }
            Text(why).font(.caption).foregroundStyle(.secondary)
        }
    }
}
