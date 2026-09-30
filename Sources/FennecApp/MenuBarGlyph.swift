import AppKit

/// The fennec in profile for the menu bar, drawn from the shapes in
/// assets/menubar-glyph.svg so it stays sharp at every scale.
enum MenuBarGlyph {
    enum Style {
        case idle
        case listening
        case working
        case attention
    }

    private static let viewBox = NSRect(x: 196, y: 120, width: 690, height: 690)
    private static let side: CGFloat = 18
    static let listeningColor = NSColor(srgbRed: 0.95, green: 0.58, blue: 0.29, alpha: 1)

    static func image(_ style: Style) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            guard let context = NSGraphicsContext.current else { return false }
            let fill = style == .listening ? listeningColor : NSColor.black
            // Draw opaque inside a layer so a translucent style fades the whole
            // fox evenly instead of darkening where the shapes overlap.
            context.cgContext.setAlpha(style == .working ? 0.45 : 1)
            context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            fill.setFill()
            for shape in silhouette() {
                shape.fill()
            }

            context.compositingOperation = .destinationOut
            cutouts().fill()
            if style == .attention {
                circle(x: 770, y: 236, radius: 116).fill()
            }
            context.compositingOperation = .sourceOver

            if style == .attention {
                fill.setFill()
                circle(x: 770, y: 236, radius: 76).fill()
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

    private static func polygon(_ points: [(CGFloat, CGFloat)]) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: point(points[0].0, points[0].1))
        for (x, y) in points.dropFirst() {
            path.line(to: point(x, y))
        }
        path.close()
        return path
    }

    /// Separate shapes, filled one by one, so overlaps never cancel out
    /// whichever way each polygon winds.
    private static func silhouette() -> [NSBezierPath] {
        let nearEar = polygon([(300, 130), (560, 470), (300, 560)])
        let farEar = polygon([(470, 170), (640, 500), (520, 460)])
        let head = polygon([
            (300, 540), (520, 440), (640, 500), (820, 650),
            (800, 690), (600, 720), (420, 800), (250, 760),
        ])
        let nose = polygon([(790, 630), (832, 650), (800, 676)])
        return [nearEar, farEar, head, nose]
    }

    private static func cutouts() -> NSBezierPath {
        let path = polygon([(330, 230), (500, 470), (340, 520)])
        path.append(polygon([(548, 562), (600, 528), (652, 560), (600, 588)]))
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
