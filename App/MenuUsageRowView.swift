import AppKit

/// Custom NSMenu row: title + usage progress bar + reset countdown.
/// Keeps a compact content width so NSMenu stretching doesn't shove % to the far right.
final class MenuUsageRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "")
    private let resetLabel = NSTextField(labelWithString: "")
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()

    private var percent: Int = 0
    private var preferredWidth: CGFloat = 200

    private let rowHeight: CGFloat = 50
    private let hInset: CGFloat = 14
    private let barHeight: CGFloat = 6
    private let percentWidth: CGFloat = 34
    private let gapBelowBar: CGFloat = 6
    private let minWidth: CGFloat = 180
    private let maxWidth: CGFloat = 220

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setup()
    }

    func configure(title: String, percent: Int, resetText: String) {
        self.percent = max(0, min(100, percent))
        titleLabel.stringValue = title
        percentLabel.stringValue = "\(self.percent)%"
        resetLabel.stringValue = "resets in \(resetText)"
        fillLayer.backgroundColor = Self.barColor(self.percent).cgColor
        sizeToContent()
    }

    func updatePercent(_ percent: Int) {
        let clamped = max(0, min(100, percent))
        guard clamped != self.percent else { return }
        self.percent = clamped
        percentLabel.stringValue = "\(clamped)%"
        fillLayer.backgroundColor = Self.barColor(clamped).cgColor
        needsLayout = true
    }

    func updateResetText(_ resetText: String) {
        let next = "resets in \(resetText)"
        guard resetLabel.stringValue != next else { return }
        resetLabel.stringValue = next
        sizeToContent()
    }

    private func setup() {
        titleLabel.font = .menuFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isSelectable = false

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        percentLabel.textColor = .secondaryLabelColor
        percentLabel.alignment = .right
        percentLabel.isSelectable = false

        resetLabel.font = .menuFont(ofSize: 11)
        resetLabel.textColor = .secondaryLabelColor
        resetLabel.lineBreakMode = .byTruncatingTail
        resetLabel.isSelectable = false

        trackLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.16).cgColor
        trackLayer.cornerRadius = 2.5
        trackLayer.masksToBounds = true

        fillLayer.cornerRadius = 2.5
        fillLayer.masksToBounds = true
        trackLayer.addSublayer(fillLayer)

        addSubview(titleLabel)
        addSubview(percentLabel)
        addSubview(resetLabel)
        layer?.addSublayer(trackLayer)
    }

    private func sizeToContent() {
        let resetW = ceil(resetLabel.sizeThatFits(NSSize(width: 10_000, height: 20)).width)
        let titleW = ceil(titleLabel.sizeThatFits(NSSize(width: 10_000, height: 20)).width)
        let rowContent = max(resetW, titleW + 8 + percentWidth)
        preferredWidth = min(maxWidth, max(minWidth, hInset * 2 + rowContent + 2))
        invalidateIntrinsicContentSize()
        setFrameSize(intrinsicContentSize)
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth, height: rowHeight)
    }

    override func layout() {
        super.layout()

        // Layout against preferred width only — ignore stretched menu bounds
        // so the % stays next to the title instead of flying to the far right.
        let width = preferredWidth
        let height = max(rowHeight, bounds.height)
        let contentW = width - hInset * 2
        let titleH: CGFloat = 16
        let resetH: CGFloat = 13
        let topPad: CGFloat = 5
        let titleToBar: CGFloat = 4

        let titleY = height - topPad - titleH
        titleLabel.frame = CGRect(x: hInset, y: titleY, width: contentW - percentWidth - 6, height: titleH)
        percentLabel.frame = CGRect(x: width - hInset - percentWidth, y: titleY, width: percentWidth, height: titleH)

        let barY = titleY - titleToBar - barHeight
        trackLayer.frame = CGRect(x: hInset, y: barY, width: contentW, height: barHeight)

        let fillW = max(percent > 0 ? 2 : 0, contentW * CGFloat(percent) / 100)
        fillLayer.frame = CGRect(x: 0, y: 0, width: fillW, height: barHeight)

        let resetY = barY - gapBelowBar - resetH
        resetLabel.frame = CGRect(x: hInset, y: max(2, resetY), width: contentW, height: resetH)
    }

    private static func barColor(_ percent: Int) -> NSColor {
        switch percent {
        case ..<50: return NSColor(calibratedRed: 0.35, green: 0.72, blue: 0.48, alpha: 1)
        case ..<75: return NSColor(calibratedRed: 0.90, green: 0.72, blue: 0.28, alpha: 1)
        case ..<90: return NSColor(calibratedRed: 0.92, green: 0.48, blue: 0.22, alpha: 1)
        default: return NSColor(calibratedRed: 0.88, green: 0.28, blue: 0.28, alpha: 1)
        }
    }
}
