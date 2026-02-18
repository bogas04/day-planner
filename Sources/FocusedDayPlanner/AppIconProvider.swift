import AppKit

enum AppIconProvider {
    static let dockIcon: NSImage = makeIcon(size: NSSize(width: 512, height: 512), template: false)
    static let menuBarIcon: NSImage = makeIcon(size: NSSize(width: 18, height: 18), template: true)

    private static func makeIcon(size: NSSize, template: Bool) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size).insetBy(dx: size.width * 0.08, dy: size.height * 0.08)
        let corner = size.width * 0.22

        if template {
            NSColor.labelColor.setFill()
        } else {
            let gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.13, green: 0.62, blue: 0.43, alpha: 1.0),
                NSColor(calibratedRed: 0.09, green: 0.49, blue: 0.35, alpha: 1.0)
            ])
            let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
            gradient?.draw(in: path, angle: -90)

            NSColor.black.withAlphaComponent(0.1).setStroke()
            path.lineWidth = size.width * 0.015
            path.stroke()
        }

        let strokePath = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
        if template {
            NSColor.labelColor.setStroke()
            strokePath.lineWidth = size.width * 0.1
            strokePath.stroke()
        }

        let checkPath = NSBezierPath()
        checkPath.move(to: NSPoint(x: rect.minX + rect.width * 0.23, y: rect.minY + rect.height * 0.52))
        checkPath.line(to: NSPoint(x: rect.minX + rect.width * 0.43, y: rect.minY + rect.height * 0.30))
        checkPath.line(to: NSPoint(x: rect.minX + rect.width * 0.77, y: rect.minY + rect.height * 0.68))
        checkPath.lineCapStyle = .round
        checkPath.lineJoinStyle = .round
        checkPath.lineWidth = size.width * (template ? 0.12 : 0.10)

        if template {
            NSColor.labelColor.setStroke()
        } else {
            NSColor.white.setStroke()
        }
        checkPath.stroke()

        image.unlockFocus()
        image.isTemplate = template
        return image
    }
}
