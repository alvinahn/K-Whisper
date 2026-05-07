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
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "K-Whisper Settings"
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

// MARK: - Sidebar-driven settings

private enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case apiKeys
    case modes
    case glossary
    case history
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:     return "General"
        case .apiKeys:     return "API Keys"
        case .modes:       return "Modes"
        case .glossary:    return "Glossary"
        case .history:     return "History"
        case .permissions: return "Permissions"
        }
    }

    var systemImage: String {
        switch self {
        case .general:     return "gearshape.fill"
        case .apiKeys:     return "key.fill"
        case .modes:       return "sparkles"
        case .glossary:    return "character.book.closed.fill"
        case .history:     return "clock.fill"
        case .permissions: return "lock.shield.fill"
        }
    }

    var iconTint: Color {
        switch self {
        case .general:     return .gray
        case .apiKeys:     return .yellow
        case .modes:       return .blue
        case .glossary:    return .purple
        case .history:     return .indigo
        case .permissions: return .green
        }
    }
}

struct SettingsRootView: View {
    @State private var selection: SettingsTab? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selection) { tab in
                NavigationLink(value: tab) {
                    Label {
                        Text(tab.title)
                            .font(.system(size: 13, weight: .medium))
                    } icon: {
                        Image(systemName: tab.systemImage)
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(tab.iconTint)
                            )
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(selection?.title ?? "Settings")
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .general {
        case .general:     GeneralSettingsView()
        case .apiKeys:     APIKeysSettingsView()
        case .modes:       ModesSettingsView()
        case .glossary:    GlossaryView()
        case .history:     HistoryView()
        case .permissions: PermissionsView()
        }
    }
}
