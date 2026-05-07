import AppKit

// Build-time helper: render the .iconset for AppIcon.icns generation.
// Usage: ./Voxa --render-iconset /path/to/AppIcon.iconset
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

// Top-level code is nonisolated; AppDelegate's @MainActor init must be entered explicitly.
// macOS guarantees the main thread for the main entry point, so assumeIsolated is safe.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
