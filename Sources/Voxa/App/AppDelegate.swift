import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide Dock icon (LSUIElement also handles this in Info.plist).
        NSApp.setActivationPolicy(.accessory)

        // Brand the Dock icon (visible whenever activation policy goes to .regular,
        // e.g. while Settings is open).
        NSApp.applicationIconImage = AppIconFactory.dockIcon()

        // Pre-warm TLS to the API hosts so the first dictation lands on a warm connection.
        Networking.prewarm()

        MainMenuBuilder.install()
        MenuBarController.shared.install()
        DictationCoordinator.shared.start()

        // Show Settings on first launch if no API key is configured.
        if !SecretsStore.shared.hasOpenAI && !SecretsStore.shared.hasAnthropic && !SecretsStore.shared.hasGoogle {
            SettingsWindowController.shared.show()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
