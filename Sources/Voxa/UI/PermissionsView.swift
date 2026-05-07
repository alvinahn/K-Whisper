import SwiftUI

struct PermissionsView: View {
    @ObservedObject private var perms = PermissionManager.shared
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var diag = Diagnostics.shared

    var body: some View {
        Form {
            Section {
                Text("Voxa needs Microphone + Accessibility for full functionality. Use the diagnostic buttons below to verify each piece independently.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            row(
                title: "Microphone",
                granted: perms.hasMicrophone,
                why: "Required to capture your voice.",
                action: { Task { _ = await perms.requestMicrophone() } },
                actionLabel: "Request",
                fallback: { perms.openMicrophonePane() }
            )

            row(
                title: "Accessibility",
                granted: perms.hasAccessibility,
                why: "Required to type the transcribed text into other apps.",
                action: { perms.requestAccessibility() },
                actionLabel: "Request",
                fallback: { perms.openAccessibilityPane() }
            )

            if settings.holdKeyEnabled && settings.holdKey == .fn {
                row(
                    title: "Input Monitoring (only needed for Fn key)",
                    granted: nil,
                    why: "Switch the hold key to Right ⌘ in General to skip this.",
                    action: nil,
                    actionLabel: nil,
                    fallback: { perms.openInputMonitoringPane() }
                )
            }

            Section("Microphone test") {
                HStack {
                    Button(diag.micTestActive ? "Stop recording" : "Start recording") {
                        diag.toggleMicTest()
                    }
                    if diag.micTestActive {
                        ProgressView(value: Double(diag.micTestLevel))
                            .frame(width: 140)
                        Text("peak \(String(format: "%.2f", diag.micTestPeak))")
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        Text(String(format: "%.1fs", diag.micTestSeconds))
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Section("Other diagnostics") {
                HStack {
                    Button("Test paste") { diag.testPaste() }
                    Button("Test Groq key") { diag.testGroqKey() }
                    Button("Test OpenAI key") { diag.testOpenAIKey() }
                    Button("Test Google key") { diag.testGoogleKey() }
                }
                HStack {
                    Button("Open Console.app for logs") { diag.openConsole() }
                    Spacer()
                }
                if !diag.lastMessage.isEmpty {
                    Text(diag.lastMessage)
                        .foregroundStyle(diag.lastSuccess ? .green : .primary)
                        .font(.system(.body, design: .monospaced))
                        .padding(.top, 6)
                }
                Text("If paste fails: re-grant Accessibility in System Settings (after unsigned rebuilds, the existing grant becomes stale).")
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
                    Text(granted ? "Granted" : "Not granted")
                } else {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.gray)
                    Text("Check in System Settings")
                }
                Spacer()
                if let action = action, let label = actionLabel {
                    Button(label, action: action)
                }
                Button("Open System Settings", action: fallback)
            }
            Text(why).font(.caption).foregroundStyle(.secondary)
        }
    }
}
