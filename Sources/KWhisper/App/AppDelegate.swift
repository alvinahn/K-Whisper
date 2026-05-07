import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Migrate Application Support folder from the old "Voxa" name to "KWhisper".
        // Must run before any singleton store is touched.
        DataMigration.runIfNeeded()

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

        // Show Settings on every launch (user-requested) — useful for verifying state,
        // checking permissions, and picking a mode before dictating.
        SettingsWindowController.shared.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
