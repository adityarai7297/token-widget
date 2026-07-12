import AppKit

/// Custom NSMenu row: title + usage progress bar + reset countdown.
final class MenuUsageRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "")
    private let resetLabel = NSTextField(labelWithString: "")
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()

    private var percent: Int = 0

    private let rowWidth: CGFloat = 248
    private let rowHeight: CGFloat = 50
    private let hInset: CGFloat = 14
    private let barHeight: CGFloat = 6
    private let percentWidth: CGFloat = 34
    private let gapBelowBar: CGFloat = 6

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
        needsLayout = true
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

    override var intrinsicContentSize: NSSize {
        NSSize(width: rowWidth, height: rowHeight)
    }

    override func layout() {
        super.layout()

        let width = max(rowWidth, bounds.width)
        let height = max(rowHeight, bounds.height)
        let contentW = width - hInset * 2
        let titleH: CGFloat = 16
        let resetH: CGFloat = 13
        let topPad: CGFloat = 5
        let titleToBar: CGFloat = 4

        // AppKit y=0 is bottom. Stack title → bar → reset from the top.
        let titleY = height - topPad - titleH
        titleLabel.frame = CGRect(x: hInset, y: titleY, width: contentW - percentWidth - 6, height: titleH)
        percentLabel.frame = CGRect(x: width - hInset - percentWidth, y: titleY, width: percentWidth, height: titleH)

        let barY = titleY - titleToBar - barHeight
        let barW = contentW
        trackLayer.frame = CGRect(x: hInset, y: barY, width: barW, height: barHeight)

        let fillW = max(percent > 0 ? 2 : 0, barW * CGFloat(percent) / 100)
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
