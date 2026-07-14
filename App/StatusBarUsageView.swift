import AppKit

/// Menu-bar strip: 5-hour usage bar + circular reset cooldown.
final class StatusBarUsageView: NSView {
    struct Model {
        var percent: Int
        var resetsAt: Date?
    }

    var model: Model = .init(percent: 0) {
        didSet { needsDisplay = true }
    }

    private let barHeight: CGFloat = 6
    private let logoSize: CGFloat = 13
    private let trackWidth: CGFloat = 48
    private let pctWidth: CGFloat = 32
    private let ringSize: CGFloat = 14
    private let hPad: CGFloat = 4
    private let sessionSeconds: TimeInterval = 5 * 3600

    override var intrinsicContentSize: NSSize {
        let minsW = cooldownLabelWidth(Formatters.compactCountdown(until: model.resetsAt))
        let width = hPad * 2
            + logoSize + 5
            + trackWidth + 4
            + pctWidth + 8
            + ringSize + 3 + minsW
        return NSSize(width: ceil(width), height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        let midY = bounds.midY
        let textH: CGFloat = 13
        let textY = midY - textH / 2
        var x = hPad

        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let minsAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.92),
        ]

        let logoRect = CGRect(
            x: x,
            y: midY - logoSize / 2,
            width: logoSize,
            height: logoSize
        )
        StatusBarIcon.drawMark(in: logoRect)
        x += logoSize + 5

        let trackY = midY - barHeight / 2
        let track = CGRect(x: x, y: trackY, width: trackWidth, height: barHeight)
        NSColor.labelColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()

        let pct = max(0, min(100, model.percent))
        let fillW = max(pct > 0 ? 2 : 0, trackWidth * CGFloat(pct) / 100)
        if fillW > 0 {
            let fill = CGRect(x: x, y: trackY, width: fillW, height: barHeight)
            barColor(pct).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 2.5, yRadius: 2.5).fill()
        }
        x += trackWidth + 4

        ("\(pct)%" as NSString).draw(
            in: CGRect(x: x, y: textY, width: pctWidth, height: textH),
            withAttributes: pctAttrs
        )
        x += pctWidth + 8

        let remaining = remainingFraction()
        let ringRect = CGRect(
            x: x,
            y: midY - ringSize / 2,
            width: ringSize,
            height: ringSize
        )
        drawCooldownRing(in: ringRect, fraction: remaining)
        x += ringSize + 3

        let minsLabel = Formatters.compactCountdown(until: model.resetsAt)
        let minsW = cooldownLabelWidth(minsLabel)
        (minsLabel as NSString).draw(
            in: CGRect(x: x, y: textY, width: minsW, height: textH),
            withAttributes: minsAttrs
        )
    }

    func rasterizedImage() -> NSImage {
        let size = intrinsicContentSize
        return NSImage(size: size, flipped: true) { [self] rect in
            bounds = rect
            draw(rect)
            return true
        }
    }

    private func remainingFraction() -> CGFloat {
        guard let resetsAt = model.resetsAt else { return 0 }
        let remaining = max(0, resetsAt.timeIntervalSinceNow)
        return CGFloat(min(1, remaining / sessionSeconds))
    }

    private func drawCooldownRing(in rect: CGRect, fraction: CGFloat) {
        let lineWidth: CGFloat = 2
        let inset = lineWidth / 2
        let circle = rect.insetBy(dx: inset, dy: inset)
        let center = CGPoint(x: circle.midX, y: circle.midY)
        let radius = min(circle.width, circle.height) / 2

        let track = NSBezierPath()
        track.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: 360,
            clockwise: false
        )
        track.lineWidth = lineWidth
        NSColor.labelColor.withAlphaComponent(0.15).setStroke()
        track.stroke()

        guard fraction > 0.001 else { return }

        let startAngle: CGFloat = 90
        let sweep = 360 * fraction
        let endAngle = startAngle - sweep

        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        ringColor(fraction: fraction).setStroke()
        arc.stroke()
    }

    private func cooldownLabelWidth(_ label: String) -> CGFloat {
        // Reserve room for second-accurate labels like "59m 59s".
        let text = (label.isEmpty ? "59m 59s" : label) as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
        ]
        return max(32, ceil(text.size(withAttributes: attrs).width) + 1)
    }

    private func barColor(_ percent: Int) -> NSColor {
        switch percent {
        case ..<50: return NSColor(calibratedRed: 0.35, green: 0.72, blue: 0.48, alpha: 1)
        case ..<75: return NSColor(calibratedRed: 0.90, green: 0.72, blue: 0.28, alpha: 1)
        case ..<90: return NSColor(calibratedRed: 0.92, green: 0.48, blue: 0.22, alpha: 1)
        default: return NSColor(calibratedRed: 0.88, green: 0.28, blue: 0.28, alpha: 1)
        }
    }

    private func ringColor(fraction: CGFloat) -> NSColor {
        switch fraction {
        case 0.5...: return NSColor(calibratedRed: 0.40, green: 0.70, blue: 0.95, alpha: 1)
        case 0.2..<0.5: return NSColor(calibratedRed: 0.90, green: 0.72, blue: 0.28, alpha: 1)
        default: return NSColor(calibratedRed: 0.92, green: 0.48, blue: 0.22, alpha: 1)
        }
    }
}
