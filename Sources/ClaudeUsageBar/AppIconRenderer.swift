import AppKit

/// Draws the app icon (a usage meter on a Claude-orange tile) so the
/// repository needs no binary assets. Used by `scripts/build_app.sh`.
enum AppIconRenderer {
    static func writePNG(to url: URL, pixels: Int = 1024) throws {
        try OffscreenCanvas.writePNG(to: url, size: NSSize(width: pixels, height: pixels), scale: 1) { _ in
            draw(side: CGFloat(pixels))
        }
    }

    private static func draw(side: CGFloat) {
        let s = side / 1024

        // macOS icon grid: 824pt tile with a 100pt margin.
        let tileRect = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let tile = NSBezierPath(roundedRect: tileRect, xRadius: 185 * s, yRadius: 185 * s)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 24 * s
        shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
        shadow.set()
        NSColor(srgbRed: 0.80, green: 0.42, blue: 0.29, alpha: 1).setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGradient(
            starting: NSColor(srgbRed: 0.91, green: 0.55, blue: 0.42, alpha: 1),
            ending: NSColor(srgbRed: 0.74, green: 0.35, blue: 0.22, alpha: 1)
        )?.draw(in: tile, angle: -90)

        // Two stacked capsule meters (session and weekly), echoing the
        // split gauge in the menu bar.
        let meters: [(y: CGFloat, fraction: CGFloat)] = [(560, 0.72), (380, 0.45)]
        for meter in meters {
            let track = NSRect(x: 232 * s, y: meter.y * s, width: 560 * s, height: 96 * s)
            let radius = track.height / 2
            NSColor.white.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

            let fill = NSRect(x: track.minX, y: track.minY, width: track.width * meter.fraction, height: track.height)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
        }
    }
}

/// Renders every menu-bar gauge style and state on light and dark bars, so
/// the glyphs can be checked without launching the app.
enum GaugePreview {
    static func writePNG(to url: URL) throws {
        let states: [(String, [Double], UsageLevel)] = [
            ("100%", [1.0], .normal),
            ("62%", [0.62], .normal),
            ("22%", [0.22], .warning),
            ("6%", [0.06], .critical),
            ("split", [0.80, 0.35], .normal),
            ("none", [], .unknown)
        ]
        let appearances: [(NSAppearance.Name, NSColor, NSColor)] = [
            (.aqua, NSColor(white: 0.93, alpha: 1), .black),
            (.darkAqua, NSColor(white: 0.16, alpha: 1), .white)
        ]

        let cellWidth: CGFloat = 84
        let rowHeight: CGFloat = 26
        let rowCount = GaugeStyle.allCases.count * appearances.count
        let size = NSSize(width: cellWidth * CGFloat(states.count), height: rowHeight * CGFloat(rowCount))

        try OffscreenCanvas.writePNG(to: url, size: size, scale: 4) { _ in
            var row = 0
            for style in GaugeStyle.allCases {
                for (appearanceName, background, tint) in appearances {
                    let y = CGFloat(rowCount - 1 - row) * rowHeight
                    row += 1
                    background.setFill()
                    NSRect(x: 0, y: y, width: size.width, height: rowHeight).fill()

                    NSAppearance(named: appearanceName)?.performAsCurrentDrawingAppearance {
                        for (index, (label, fills, level)) in states.enumerated() {
                            let image = GaugeRenderer.image(for: Gauge(style: style, fills: fills, level: level))
                            let origin = NSPoint(x: CGFloat(index) * cellWidth + 8,
                                                 y: y + (rowHeight - image.size.height) / 2)
                            let drawable = image.isTemplate ? tinted(image, with: tint) : image
                            drawable.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)

                            NSAttributedString(string: label, attributes: [
                                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                                .foregroundColor: tint
                            ]).draw(at: NSPoint(x: origin.x + image.size.width + 5, y: y + 7))
                        }
                    }
                }
            }
        }
    }

    /// Mimics how the menu bar tints template images.
    private static func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}

enum OffscreenCanvas {
    static func writePNG(to url: URL, size: NSSize, scale: CGFloat, draw: (NSSize) -> Void) throws {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw UsageError.iconRender("could not allocate bitmap")
        }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(size)
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw UsageError.iconRender("could not encode PNG")
        }
        try data.write(to: url, options: .atomic)
    }
}
