import AppKit

/// The fennec head for the menu bar, drawn from the shapes in
/// assets/menubar-glyph.svg so it stays sharp at every scale.
enum MenuBarGlyph {
    enum Style {
        case idle
        case listening
        case working
        case attention
    }

    private static let viewBox = NSRect(x: 160, y: 120, width: 704, height: 704)
    private static let side: CGFloat = 18
    private static let listeningColor = NSColor(srgbRed: 0.95, green: 0.58, blue: 0.29, alpha: 1)

    static func image(_ style: Style) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            guard let context = NSGraphicsContext.current else { return false }
            let fill = style == .listening ? listeningColor : NSColor.black
            // Draw opaque inside a layer so a translucent style fades the whole
            // head evenly instead of darkening where the shapes overlap.
            context.cgContext.setAlpha(style == .working ? 0.45 : 1)
            context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            fill.setFill()
            for shape in silhouette() {
                shape.fill()
            }

            context.compositingOperation = .destinationOut
            cutouts().fill()
            if style == .attention {
                circle(x: 764, y: 724, radius: 116).fill()
            }
            context.compositingOperation = .sourceOver

            if style == .attention {
                fill.setFill()
                circle(x: 764, y: 724, radius: 76).fill()
            }
            context.cgContext.endTransparencyLayer()
            return true
        }
        image.isTemplate = style != .listening
        image.accessibilityDescription = "Fennec"
        return image
    }

    private static func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        let scale = side / viewBox.width
        return NSPoint(x: (x - viewBox.minX) * scale, y: (y - viewBox.minY) * scale)
    }

    private static func curve(
        _ path: NSBezierPath,
        _ c1x: CGFloat, _ c1y: CGFloat,
        _ c2x: CGFloat, _ c2y: CGFloat,
        _ x: CGFloat, _ y: CGFloat
    ) {
        path.curve(to: point(x, y), controlPoint1: point(c1x, c1y), controlPoint2: point(c2x, c2y))
    }

    private static func ear(_ path: NSBezierPath, mirrored: Bool, inner: Bool) {
        // Left ear coordinates; the right ear mirrors them around x = 512.
        let m: (CGFloat) -> CGFloat = { mirrored ? 1024 - $0 : $0 }
        if inner {
            path.move(to: point(m(430), 500))
            curve(path, m(398), 410, m(322), 300, m(250), 236)
            curve(path, m(250), 330, m(274), 436, m(330), 510)
        } else {
            path.move(to: point(m(472), 474))
            curve(path, m(430), 360, m(322), 226, m(196), 140)
            curve(path, m(182), 290, m(214), 456, m(322), 568)
        }
        path.close()
    }

    /// Separate shapes, filled one by one: the mirrored ear winds the other
    /// way, so a single path would cancel out where the ears overlap the head.
    private static func silhouette() -> [NSBezierPath] {
        let left = NSBezierPath()
        ear(left, mirrored: false, inner: false)
        let right = NSBezierPath()
        ear(right, mirrored: true, inner: false)
        let head = NSBezierPath()
        head.move(to: point(512, 800))
        curve(head, 456, 794, 356, 700, 300, 610)
        curve(head, 290, 520, 400, 452, 512, 450)
        curve(head, 624, 452, 734, 520, 724, 610)
        curve(head, 668, 700, 568, 794, 512, 800)
        head.close()
        return [left, right, head]
    }

    private static func cutouts() -> NSBezierPath {
        let path = NSBezierPath()
        ear(path, mirrored: false, inner: true)
        ear(path, mirrored: true, inner: true)
        path.append(ellipse(x: 440, y: 596, rx: 36, ry: 42))
        path.append(ellipse(x: 584, y: 596, rx: 36, ry: 42))
        return path
    }

    private static func ellipse(x: CGFloat, y: CGFloat, rx: CGFloat, ry: CGFloat) -> NSBezierPath {
        let origin = point(x - rx, y - ry)
        let corner = point(x + rx, y + ry)
        return NSBezierPath(ovalIn: NSRect(x: origin.x, y: origin.y, width: corner.x - origin.x, height: corner.y - origin.y))
    }

    private static func circle(x: CGFloat, y: CGFloat, radius: CGFloat) -> NSBezierPath {
        ellipse(x: x, y: y, rx: radius, ry: radius)
    }
}
