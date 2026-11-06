import AppKit

/// What the menu-bar gauge should show.
struct Gauge: Equatable {
    var style: GaugeStyle
    /// Remaining fractions from 0 to 1. One value draws a single gauge, two
    /// values draw a split gauge (session first, weekly second). An empty
    /// array draws only the empty track (no data yet).
    var fills: [Double]
    var level: UsageLevel
}

/// Draws the status-bar gauge.
///
/// In normal state the image is a template, so the system tints it for light
/// and dark menu bars. In warning or critical state the fill is colored and
/// the track uses the dynamic label color.
enum GaugeRenderer {
    private static let trackAlpha: CGFloat = 0.28

    static func image(for gauge: Gauge) -> NSImage {
        let isTemplate = gauge.level == .normal || gauge.level == .unknown
        let size: NSSize
        switch gauge.style {
        case .bar: size = NSSize(width: 32, height: 16)
        case .segments: size = NSSize(width: 33, height: 16)
        case .ring: size = NSSize(width: 16, height: 16)
        }

        let image = NSImage(size: size, flipped: false) { _ in
            let ink: NSColor = isTemplate ? .black : .labelColor
            let colors = Colors(
                track: ink.withAlphaComponent(trackAlpha),
                fill: fillColor(for: gauge.level)
            )
            switch gauge.style {
            case .bar: drawBar(gauge.fills, colors)
            case .segments: drawSegments(gauge.fills, colors)
            case .ring: drawRing(gauge.fills, colors)
            }
            return true
        }
        image.isTemplate = isTemplate
        image.accessibilityDescription = "Claude usage"
        return image
    }

    private struct Colors {
        let track: NSColor
        let fill: NSColor
    }

    private static func fillColor(for level: UsageLevel) -> NSColor {
        switch level {
        case .critical: return .systemRed
        case .warning: return .systemOrange
        case .normal, .unknown: return .black
        }
    }

    // MARK: Bar: a capsule progress bar.

    private static func drawBar(_ fills: [Double], _ colors: Colors) {
        let rows: [NSRect] = fills.count >= 2
            ? [NSRect(x: 1, y: 9, width: 30, height: 4), NSRect(x: 1, y: 3, width: 30, height: 4)]
            : [NSRect(x: 1, y: 5, width: 30, height: 6)]

        for (index, track) in rows.enumerated() {
            let radius = track.height / 2
            colors.track.setFill()
            NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

            guard index < fills.count else { continue }
            let fraction = CGFloat(clamp(fills[index]))
            guard fraction > 0 else { continue }
            let width = max(track.height, track.width * fraction)
            let fill = NSRect(x: track.minX, y: track.minY, width: width, height: track.height)
            colors.fill.setFill()
            NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
        }
    }

    // MARK: Segments: discrete blocks, like a level meter.

    private static let segmentCount = 8

    private static func drawSegments(_ fills: [Double], _ colors: Colors) {
        let rows: [(y: CGFloat, height: CGFloat)] = fills.count >= 2
            ? [(9, 4), (3, 4)]
            : [(3.5, 9)]
        let width: CGFloat = 3
        let gap: CGFloat = 1

        for (index, row) in rows.enumerated() {
            let fraction = index < fills.count ? clamp(fills[index]) : 0
            var lit = Int((fraction * Double(segmentCount)).rounded())
            if fraction > 0 { lit = max(1, lit) }

            for segment in 0..<segmentCount {
                let rect = NSRect(x: 1 + CGFloat(segment) * (width + gap), y: row.y,
                                  width: width, height: row.height)
                (segment < lit ? colors.fill : colors.track).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            }
        }
    }

    // MARK: Ring: a circular gauge, concentric rings when split.

    private static func drawRing(_ fills: [Double], _ colors: Colors) {
        let center = NSPoint(x: 8, y: 8)
        let rings: [(radius: CGFloat, lineWidth: CGFloat)] = fills.count >= 2
            ? [(6.4, 1.9), (3.4, 1.9)]
            : [(6, 2.4)]

        for (index, ring) in rings.enumerated() {
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: ring.radius, startAngle: 0, endAngle: 360)
            track.lineWidth = ring.lineWidth
            colors.track.setStroke()
            track.stroke()

            guard index < fills.count else { continue }
            let fraction = CGFloat(clamp(fills[index]))
            guard fraction > 0 else { continue }
            // Clockwise from 12 o'clock.
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: ring.radius,
                          startAngle: 90, endAngle: 90 - 360 * min(fraction, 0.999), clockwise: true)
            arc.lineWidth = ring.lineWidth
            arc.lineCapStyle = .round
            colors.fill.setStroke()
            arc.stroke()
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
