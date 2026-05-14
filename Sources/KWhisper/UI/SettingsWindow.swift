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
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "K-Whisper 설정"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
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
    case onboarding
    case general
    case apiKeys
    case modes
    case glossary
    case history
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onboarding:  return "시작하기"
        case .general:     return "일반"
        case .apiKeys:     return "API 키"
        case .modes:       return "모드"
        case .glossary:    return "용어집"
        case .history:     return "기록"
        case .permissions: return "권한"
        }
    }

    var systemImage: String {
        switch self {
        case .onboarding:  return "checklist"
        case .general:     return "gearshape.fill"
        case .apiKeys:     return "key.fill"
        case .modes:       return "sparkles"
        case .glossary:    return "character.book.closed.fill"
        case .history:     return "clock.fill"
        case .permissions: return "lock.shield.fill"
        }
    }

    /// Slightly desaturated tints, closer to the native macOS Settings sidebar feel
    /// than the stock Color.yellow / Color.blue (which read as neon).
    var iconTint: Color {
        switch self {
        case .onboarding:  return Color(red: 0.22, green: 0.58, blue: 0.86)
        case .general:     return Color(red: 0.50, green: 0.50, blue: 0.55)
        case .apiKeys:     return Color(red: 0.86, green: 0.66, blue: 0.18)
        case .modes:       return Color(red: 0.20, green: 0.50, blue: 0.92)
        case .glossary:    return Color(red: 0.62, green: 0.42, blue: 0.85)
        case .history:     return Color(red: 0.42, green: 0.40, blue: 0.85)
        case .permissions: return Color(red: 0.30, green: 0.65, blue: 0.40)
        }
    }
}

struct SettingsRootView: View {
    @State private var selection: SettingsTab? = .onboarding

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selection) { tab in
                Label {
                    Text(tab.title)
                        .font(.system(size: 13, weight: .medium))
                } icon: {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.96))
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [tab.iconTint, tab.iconTint.opacity(0.82)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                }
                .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(selection ?? .onboarding)
                .navigationTitle(selection?.title ?? "설정")
                .navigationSubtitle("")
                .toolbar {
                    ToolbarItem(placement: .navigation) { Spacer() }
                }
        }
        .frame(minWidth: 880, minHeight: 580)
        .toolbarBackground(.visible, for: .windowToolbar)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .onboarding {
        case .onboarding:  OnboardingView()
        case .general:     GeneralSettingsView()
        case .apiKeys:     APIKeysSettingsView()
        case .modes:       ModesSettingsView()
        case .glossary:    GlossaryView()
        case .history:     HistoryView()
        case .permissions: PermissionsView()
        }
    }
}
