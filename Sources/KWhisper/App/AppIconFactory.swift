import AppKit

/// Programmatically renders K-Whisper's brand mark for the Dock icon and menu bar.
/// The mark: a "voice meter" — 7 audio bars in a soft bell silhouette, evoking sound.
@MainActor
enum AppIconFactory {

    private static let voxaPurple = NSColor(srgbRed: 0.45, green: 0.20, blue: 0.95, alpha: 1.0)
    private static let voxaPink   = NSColor(srgbRed: 0.95, green: 0.30, blue: 0.55, alpha: 1.0)
    private static let voxaIndigo = NSColor(srgbRed: 0.30, green: 0.10, blue: 0.85, alpha: 1.0)

    /// 1024×1024 colorful Dock icon: gradient square + white speech bubble + audio bars.
    static func dockIcon() -> NSImage {
        dockIcon(pixelSize: 1024)
    }

    /// Renders a square dock-style icon at the requested pixel size.
    static func dockIcon(pixelSize: CGFloat) -> NSImage {
        let size = NSSize(width: pixelSize, height: pixelSize)
        return NSImage(size: size, flipped: false) { rect in
            let scale = pixelSize / 1024.0

            let cornerRadius: CGFloat = 232 * scale
            let bg = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            bg.addClip()

            let gradient = NSGradient(colors: [voxaIndigo, voxaPink])!
            gradient.draw(in: rect, angle: 135)

            if let highlight = NSGradient(colors: [
                NSColor.white.withAlphaComponent(0.18),
                NSColor.white.withAlphaComponent(0.0)
            ]) {
                highlight.draw(in: NSRect(x: 0, y: rect.height * 0.55, width: rect.width, height: rect.height * 0.45), angle: 270)
            }

            let bubbleRect = NSRect(
                x: 188 * scale, y: 300 * scale,
                width: 648 * scale, height: 460 * scale
            )
            let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 110 * scale, yRadius: 110 * scale)
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: 308 * scale, y: 320 * scale))
            tail.curve(to: NSPoint(x: 250 * scale, y: 200 * scale),
                       controlPoint1: NSPoint(x: 282 * scale, y: 282 * scale),
                       controlPoint2: NSPoint(x: 246 * scale, y: 240 * scale))
            tail.curve(to: NSPoint(x: 408 * scale, y: 320 * scale),
                       controlPoint1: NSPoint(x: 330 * scale, y: 268 * scale),
                       controlPoint2: NSPoint(x: 376 * scale, y: 296 * scale))
            tail.close()

            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
            shadow.shadowBlurRadius = 24 * scale
            shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
            NSGraphicsContext.current?.saveGraphicsState()
            shadow.set()
            NSColor.white.setFill()
            bubble.fill()
            tail.fill()
            NSGraphicsContext.current?.restoreGraphicsState()

            let heights: [CGFloat] = [70, 150, 230, 290, 230, 150, 70].map { $0 * scale }
            let barWidth: CGFloat  = 38 * scale
            let spacing: CGFloat   = 22 * scale
            let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * spacing
            var x: CGFloat = (size.width - totalWidth) / 2
            let centerY: CGFloat = bubbleRect.midY

            for h in heights {
                let r = NSRect(x: x, y: centerY - h/2, width: barWidth, height: h)
                let path = NSBezierPath(roundedRect: r, xRadius: barWidth/2, yRadius: barWidth/2)
                NSGraphicsContext.current?.saveGraphicsState()
                path.addClip()
                let g = NSGradient(colors: [voxaPurple, voxaPink])!
                g.draw(in: r, angle: 90)
                NSGraphicsContext.current?.restoreGraphicsState()
                x += barWidth + spacing
            }
            return true
        }
    }

    /// Writes the macOS iconset (PNGs at all required sizes) to `directoryURL`.
    /// Caller should run `iconutil -c icns` on it afterwards.
    static func writeIconset(to directoryURL: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let entries: [(name: String, pixels: CGFloat)] = [
            ("icon_16x16.png",      16),
            ("icon_16x16@2x.png",   32),
            ("icon_32x32.png",      32),
            ("icon_32x32@2x.png",   64),
            ("icon_128x128.png",    128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png",    256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png",    512),
            ("icon_512x512@2x.png", 1024),
        ]
        for entry in entries {
            let img = dockIcon(pixelSize: entry.pixels)
            guard let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "AppIconFactory", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to render \(entry.name)"
                ])
            }
            try png.write(to: directoryURL.appendingPathComponent(entry.name))
        }
    }

    /// 22×18 monochrome menu bar icon (template image — auto-tinted by the system).
    /// Same audio-meter glyph, so the brand reads consistently in both places.
    static func menuBarIcon() -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            let heights: [CGFloat] = [4.0, 7.0, 11.0, 14.0, 11.0, 7.0, 4.0]
            let barWidth: CGFloat = 1.6
            let spacing: CGFloat = 0.95
            let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * spacing
            var x: CGFloat = (rect.width - totalWidth) / 2
            NSColor.black.setFill()
            for h in heights {
                let r = NSRect(x: x, y: (rect.height - h) / 2, width: barWidth, height: h)
                NSBezierPath(roundedRect: r, xRadius: barWidth/2, yRadius: barWidth/2).fill()
                x += barWidth + spacing
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    /// Renders the DMG installer window background (540×380) with the brand gradient,
    /// title text, and a horizontal arrow between the icon positions used by `make-dmg.sh`.
    /// Writes a PNG to `url`.
    static func writeDMGBackground(to url: URL) throws {
        let size = NSSize(width: 540, height: 380)
        let img = NSImage(size: size, flipped: false) { rect in
            // Darker gradient so white text + white arrow have stronger contrast.
            let bg = NSGradient(colors: [
                NSColor(srgbRed: 0.06, green: 0.06, blue: 0.10, alpha: 1),
                NSColor(srgbRed: 0.13, green: 0.11, blue: 0.18, alpha: 1)
            ])!
            bg.draw(in: rect, angle: 90)

            // Indigo accent stripe across the top
            let accent = NSGradient(colors: [voxaIndigo.withAlphaComponent(0.0), voxaIndigo.withAlphaComponent(0.45), voxaIndigo.withAlphaComponent(0.0)])!
            accent.draw(in: NSRect(x: 0, y: rect.height - 4, width: rect.width, height: 4), angle: 0)

            // Drop-shadow for the title so it pops against the gradient.
            let titleShadow = NSShadow()
            titleShadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
            titleShadow.shadowBlurRadius = 6
            titleShadow.shadowOffset = NSSize(width: 0, height: -1)

            // Title — bigger, bolder, with shadow
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .center
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: titleStyle,
                .shadow: titleShadow
            ]
            let title = "Install K-Whisper" as NSString
            let titleSize = title.size(withAttributes: titleAttrs)
            title.draw(
                at: NSPoint(x: (rect.width - titleSize.width) / 2, y: rect.height - 60),
                withAttributes: titleAttrs
            )

            // Subtitle — bigger, more opaque
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92),
                .shadow: titleShadow
            ]
            let subtitle = "Drag K-Whisper onto the Applications folder" as NSString
            let subSize = subtitle.size(withAttributes: subAttrs)
            subtitle.draw(
                at: NSPoint(x: (rect.width - subSize.width) / 2, y: rect.height - 92),
                withAttributes: subAttrs
            )

            // Arrow between icon positions — brighter for visibility.
            let arrowY: CGFloat = 200
            let startX: CGFloat = 200
            let endX: CGFloat   = 340
            let stroke = NSColor.white.withAlphaComponent(0.85)
            stroke.setStroke()

            let line = NSBezierPath()
            line.lineWidth = 3.5
            line.lineCapStyle = .round
            line.move(to: NSPoint(x: startX, y: arrowY))
            line.line(to: NSPoint(x: endX - 4, y: arrowY))
            line.stroke()

            // Arrowhead — filled triangle at the end
            let head = NSBezierPath()
            head.move(to: NSPoint(x: endX + 10, y: arrowY))
            head.line(to: NSPoint(x: endX - 6, y: arrowY + 10))
            head.line(to: NSPoint(x: endX - 6, y: arrowY - 10))
            head.close()
            stroke.setFill()
            head.fill()

            return true
        }

        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "AppIconFactory", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "DMG background render failed"
            ])
        }
        try png.write(to: url)
    }
}
