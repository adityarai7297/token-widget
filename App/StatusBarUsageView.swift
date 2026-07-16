import AppKit

/// Menu-bar strip: usage bar + circular reset cooldown (or a Sign in prompt).
final class StatusBarUsageView: NSView {
    struct Model {
        var percent: Int = 0
        var resetsAt: Date?
        /// Tiny owner badge (e.g. "W" when weekly owns the strip).
        var badge: String?
        /// ≥90% on 5H or weekly — orange accents without changing ownership.
        var nearLimit: Bool = false
        /// Signed-out: show “Sign in” instead of a fake 0% bar.
        var showSignIn: Bool = false
    }

    var model: Model = .init() {
        didSet { needsDisplay = true }
    }

    private let barHeight: CGFloat = 6
    private let logoSize: CGFloat = 13
    private let trackWidth: CGFloat = 48
    private let pctWidth: CGFloat = 32
    private let ringSize: CGFloat = 14
    private let badgeWidth: CGFloat = 12
    private let hPad: CGFloat = 4
    private let sessionSeconds: TimeInterval = 5 * 3600

    override var intrinsicContentSize: NSSize {
        if model.showSignIn {
            let labelW = ("Sign in" as NSString).size(
                withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]
            ).width
            return NSSize(width: ceil(hPad * 2 + logoSize + 6 + labelW), height: 18)
        }
        let minsW = cooldownLabelWidth(Formatters.compactCountdown(until: model.resetsAt))
        let badgeExtra: CGFloat = model.badge == nil ? 0 : badgeWidth + 3
        let width = hPad * 2
            + logoSize + 5
            + trackWidth + 4
            + pctWidth + 8
            + badgeExtra
            + ringSize + 3 + minsW
        return NSSize(width: ceil(width), height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        let midY = bounds.midY
        let textH: CGFloat = 13
        let textY = midY - textH / 2
        var x = hPad

        let logoRect = CGRect(
            x: x,
            y: midY - logoSize / 2,
            width: logoSize,
            height: logoSize
        )
        StatusBarIcon.drawMark(in: logoRect)
        x += logoSize + 5

        if model.showSignIn {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
            ("Sign in" as NSString).draw(
                in: CGRect(x: x, y: textY, width: bounds.width - x - hPad, height: textH),
                withAttributes: attrs
            )
            return
        }

        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let minsAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.92),
        ]

        let trackY = midY - barHeight / 2
        let track = CGRect(x: x, y: trackY, width: trackWidth, height: barHeight)
        NSColor.labelColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()

        let pct = max(0, min(100, model.percent))
        let fillW = max(pct > 0 ? 2 : 0, trackWidth * CGFloat(pct) / 100)
        if fillW > 0 {
            let fill = CGRect(x: x, y: trackY, width: fillW, height: barHeight)
            barColor(pct, nearLimit: model.nearLimit).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 2.5, yRadius: 2.5).fill()
        }
        x += trackWidth + 4

        ("\(pct)%" as NSString).draw(
            in: CGRect(x: x, y: textY, width: pctWidth, height: textH),
            withAttributes: pctAttrs
        )
        x += pctWidth + 8

        if let badge = model.badge, !badge.isEmpty {
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.85),
            ]
            (badge as NSString).draw(
                in: CGRect(x: x, y: textY + 1, width: badgeWidth, height: textH),
                withAttributes: badgeAttrs
            )
            x += badgeWidth + 3
        }

        let remaining = remainingFraction()
        let ringRect = CGRect(
            x: x,
            y: midY - ringSize / 2,
            width: ringSize,
            height: ringSize
        )
        drawCooldownRing(in: ringRect, fraction: remaining, nearLimit: model.nearLimit, exhausted: pct >= 100)
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

    private func drawCooldownRing(in rect: CGRect, fraction: CGFloat, nearLimit: Bool, exhausted: Bool) {
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
        ringColor(fraction: fraction, nearLimit: nearLimit, exhausted: exhausted).setStroke()
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

    private func barColor(_ percent: Int, nearLimit: Bool) -> NSColor {
        if percent >= 100 {
            return NSColor(calibratedRed: 0.88, green: 0.28, blue: 0.28, alpha: 1)
        }
        if nearLimit || percent >= 90 {
            return NSColor(calibratedRed: 0.92, green: 0.55, blue: 0.18, alpha: 1)
        }
        switch percent {
        case ..<50: return NSColor(calibratedRed: 0.35, green: 0.72, blue: 0.48, alpha: 1)
        case ..<75: return NSColor(calibratedRed: 0.90, green: 0.72, blue: 0.28, alpha: 1)
        default: return NSColor(calibratedRed: 0.92, green: 0.48, blue: 0.22, alpha: 1)
        }
    }

    private func ringColor(fraction: CGFloat, nearLimit: Bool, exhausted: Bool) -> NSColor {
        if exhausted {
            return NSColor(calibratedRed: 0.88, green: 0.28, blue: 0.28, alpha: 1)
        }
        if nearLimit {
            return NSColor(calibratedRed: 0.92, green: 0.55, blue: 0.18, alpha: 1)
        }
        switch fraction {
        case 0.5...: return NSColor(calibratedRed: 0.40, green: 0.70, blue: 0.95, alpha: 1)
        case 0.2..<0.5: return NSColor(calibratedRed: 0.90, green: 0.72, blue: 0.28, alpha: 1)
        default: return NSColor(calibratedRed: 0.92, green: 0.48, blue: 0.22, alpha: 1)
        }
    }
}
