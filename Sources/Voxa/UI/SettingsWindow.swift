import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        // Promote to a regular app while Settings is visible:
        //  - gives us a Dock icon so the window can be brought back via ⌘-Tab / Dock click
        //  - lets the app become active and keep window on top of other apps it's not interacting with
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsRootView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Voxa Settings"
        window.contentViewController = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Drop back to a menu-bar-only accessory app once Settings closes.
        // setActivationPolicy(.accessory) alone doesn't hide the Dock icon when the
        // app is still the active one — macOS only re-evaluates Dock visibility
        // when the app deactivates. Hiding the app forces focus to the previous
        // app and lets the policy change take visual effect immediately.
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            NSApp.hide(nil)
        }
    }
}

struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            APIKeysSettingsView()
                .tabItem { Label("API Keys", systemImage: "key.fill") }
            ModesSettingsView()
                .tabItem { Label("Modes", systemImage: "wand.and.stars") }
            GlossaryView()
                .tabItem { Label("Glossary", systemImage: "character.book.closed") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            PermissionsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 520)
    }
}
