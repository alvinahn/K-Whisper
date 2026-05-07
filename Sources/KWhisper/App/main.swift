import AppKit

// Build-time helper: render the .iconset for AppIcon.icns generation.
// Usage: ./K-Whisper --render-iconset /path/to/AppIcon.iconset
let args = CommandLine.arguments
if args.count >= 3, args[1] == "--render-iconset" {
    let dir = URL(fileURLWithPath: args[2])
    do {
        try MainActor.assumeIsolated {
            try AppIconFactory.writeIconset(to: dir)
        }
        print("Wrote iconset to \(dir.path)")
        exit(0)
    } catch {
        FileHandle.standardError.write("Failed: \(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }
}

// Build-time helper: render DMG installer window background.
// Usage: ./K-Whisper --render-dmg-background /path/to/background.png
if args.count >= 3, args[1] == "--render-dmg-background" {
    let url = URL(fileURLWithPath: args[2])
    do {
        try MainActor.assumeIsolated {
            try AppIconFactory.writeDMGBackground(to: url)
        }
        print("Wrote DMG background to \(url.path)")
        exit(0)
    } catch {
        FileHandle.standardError.write("Failed: \(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }
}

// Build-time helper: copy the system icon of one file/folder onto another.
// Used by make-dmg.sh to give the Applications alias the real folder icon.
// Usage: ./K-Whisper --copy-icon /Applications /Volumes/K-Whisper/Applications
if args.count >= 4, args[1] == "--copy-icon" {
    let src = args[2]
    let dst = args[3]
    MainActor.assumeIsolated {
        let icon = NSWorkspace.shared.icon(forFile: src)
        let ok = NSWorkspace.shared.setIcon(icon, forFile: dst, options: [])
        if ok {
            print("Copied icon from \(src) → \(dst)")
        } else {
            FileHandle.standardError.write("setIcon returned false for \(dst)\n".data(using: .utf8)!)
        }
    }
    exit(0)
}

// Top-level code is nonisolated; AppDelegate's @MainActor init must be entered explicitly.
// macOS guarantees the main thread for the main entry point, so assumeIsolated is safe.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
