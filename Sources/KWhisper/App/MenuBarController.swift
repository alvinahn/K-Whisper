import AppKit
import Combine

@MainActor
final class MenuBarController {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var modeSubscription: AnyCancellable?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = AppIconFactory.menuBarIcon()
            button.imagePosition = .imageOnly
        }
        item.menu = buildMenu()
        statusItem = item

        // Rebuild menu when modes change so the "Run with mode" submenu stays in sync.
        modeSubscription = ModeManager.shared.$modes.sink { [weak self] _ in
            self?.statusItem?.menu = self?.buildMenu()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let title = NSMenuItem(title: "K-Whisper", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        menu.addItem(NSMenuItem.separator())

        let toggle = NSMenuItem(title: "Start / stop dictation", action: #selector(triggerToggle), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let modeMenu = NSMenu(title: "Run next with mode")
        for mode in ModeManager.shared.modes {
            let item = NSMenuItem(title: mode.name, action: #selector(setNextMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.id
            modeMenu.addItem(item)
        }
        let modeParent = NSMenuItem(title: "Run next with mode", action: nil, keyEquivalent: "")
        modeParent.submenu = modeMenu
        menu.addItem(modeParent)

        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit K-Whisper", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func triggerToggle() {
        // Synthesize a toggle by calling coordinator directly through hotkey path.
        DictationCoordinator.shared.handleToggleFromMenu()
    }

    @objc private func setNextMode(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String {
            DictationCoordinator.shared.selectNextMode(id)
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    /// Same as openSettings, exposed via a public selector for the main menu.
    @objc func openSettingsAction() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
