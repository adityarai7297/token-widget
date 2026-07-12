import AppKit

enum StatusBarIcon {
    /// Claude brand orange (Crail).
    static let brandOrange = NSColor(calibratedRed: 0.82, green: 0.37, blue: 0.24, alpha: 1)

    /// Claude asterisk / starburst mark for menu-bar size.
    static func claudeMark(size: CGFloat = 13) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            drawMark(in: rect, color: brandOrange)
            return true
        }
        image.isTemplate = false
        return image
    }

    static func drawMark(in rect: CGRect, color: NSColor = brandOrange) {
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
