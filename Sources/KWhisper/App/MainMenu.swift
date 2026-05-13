import AppKit

/// Builds the standard main menu (App + Edit + Window) for K-Whisper.
/// Without an Edit menu and Paste shortcut, ⌘V isn't routed to text fields.
@MainActor
enum MainMenuBuilder {
    static func install() {
        let main = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "K-Whisper")
        appMenu.addItem(NSMenuItem(title: "K-Whisper 정보", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "설정…", action: #selector(MenuBarController.openSettingsAction), keyEquivalent: ",")
        settings.target = MenuBarController.shared
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "K-Whisper 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "다른 항목 가리기", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: "모두 보기", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "K-Whisper 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        main.addItem(appMenuItem)

        // Edit menu — required so ⌘C / ⌘V / ⌘X / ⌘A work in text fields.
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(NSMenuItem(title: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "다시 실행", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        let pasteMatchStyle = NSMenuItem(title: "스타일 맞춰 붙여넣기", action: Selector(("pasteAsPlainText:")), keyEquivalent: "V")
        pasteMatchStyle.keyEquivalentModifierMask = [.command, .option, .shift]
        editMenu.addItem(pasteMatchStyle)
        editMenu.addItem(NSMenuItem(title: "삭제", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(title: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        main.addItem(editMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "윈도우")
        windowMenu.addItem(NSMenuItem(title: "창 닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "확대/축소", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: "모두 앞으로 가져오기", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        windowMenuItem.submenu = windowMenu
        main.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }
}
