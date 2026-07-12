import AppKit

enum StatusBarIcon {
    /// Claude brand orange (Crail) — used if the asset fails to load.
    static let brandOrange = NSColor(calibratedRed: 0.82, green: 0.37, blue: 0.24, alpha: 1)

    private static let markImage: NSImage? = {
        if let url = Bundle.main.url(forResource: "ClaudeMark", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = false
            return image
        }
        return nil
    }()

    /// Claude mark for menu-bar size.
    static func claudeMark(size: CGFloat = 13) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            drawMark(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    static func drawMark(in rect: CGRect, color: NSColor = brandOrange) {
        if let markImage {
            let inset = rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04)
            markImage.draw(
                in: inset,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            return
        }

        // Fallback asterisk if the bundled asset is missing.
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) * 0.48
        let inner = outer * 0.28
        let points = 4

        let path = NSBezierPath()
        for i in 0..<(points * 2) {
            let angle = (CGFloat(i) / CGFloat(points * 2)) * .pi * 2 - .pi / 2
            let radius = i.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }
        path.close()
        color.setFill()
        path.fill()
    }
}
