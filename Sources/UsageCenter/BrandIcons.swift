import AppKit
import SwiftUI
import UsageCenterCore

public enum BrandIconRenderer {
    public static func brandAccentColor(for provider: ProviderID) -> NSColor {
        switch provider {
        case .claude:
            return NSColor(srgbRed: 0.855, green: 0.467, blue: 0.337, alpha: 1.0) // Terracotta #DA7756
        case .chatgpt:
            return NSColor(srgbRed: 0.063, green: 0.639, blue: 0.498, alpha: 1.0) // Emerald #10A37F
        case .antigravity:
            return NSColor(srgbRed: 0.290, green: 0.565, blue: 0.988, alpha: 1.0) // Orbital Blue #4A90FC
        case .deepseek:
            return NSColor(srgbRed: 0.302, green: 0.420, blue: 0.996, alpha: 1.0) // DeepSeek Blue #4D6BFE
        }
    }

    public static func swiftUIAccent(for provider: ProviderID) -> Color {
        switch provider {
        case .claude:
            return Color(red: 0.855, green: 0.467, blue: 0.337)
        case .chatgpt:
            return Color(red: 0.063, green: 0.639, blue: 0.498)
        case .antigravity:
            return Color(red: 0.290, green: 0.565, blue: 0.988)
        case .deepseek:
            return Color(red: 0.302, green: 0.420, blue: 0.996)
        }
    }

    public static func statusIcon(
        for provider: ProviderID,
        size: CGFloat = 15,
        mode: IconColorMode = .brand,
        tintOverride: NSColor? = nil
    ) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let fg: NSColor
            if let tintOverride {
                fg = tintOverride
            } else {
                fg = (mode == .brand) ? brandAccentColor(for: provider) : .labelColor
            }
            drawMark(provider: provider, in: rect.insetBy(dx: 0.8, dy: 0.8), color: fg)
            return true
        }
        img.isTemplate = (mode == .monochrome && tintOverride == nil)
        return img
    }

    public static func drawMark(provider: ProviderID, in rect: NSRect, color: NSColor) {
        NSGraphicsContext.current?.saveGraphicsState()
        defer { NSGraphicsContext.current?.restoreGraphicsState() }

        switch provider {
        case .claude:
            drawClaudeBurst(in: rect, color: color)
        case .chatgpt:
            drawOpenAIKnot(in: rect, color: color)
        case .antigravity:
            drawAntigravityOrbit(in: rect, color: color)
        case .deepseek:
            drawDeepSeekWhale(in: rect, color: color)
        }
    }

    // Claude: 10-ray organic sunburst mark
    private static func drawClaudeBurst(in rect: NSRect, color: NSColor) {
        let cx = rect.midX
        let cy = rect.midY
        let outer = min(rect.width, rect.height) * 0.48
        let inner = outer * 0.22
        let rayCount = 10

        color.setStroke()
        for i in 0..<rayCount {
            let baseAngle = Double(i) * (2.0 * .pi / Double(rayCount)) + 0.18
            let lengthFactor = (i % 2 == 0) ? 1.0 : 0.78
            let r = outer * CGFloat(lengthFactor)

            let path = NSBezierPath()
            path.move(to: NSPoint(
                x: cx + inner * CGFloat(cos(baseAngle)),
                y: cy + inner * CGFloat(sin(baseAngle))
            ))
            path.line(to: NSPoint(
                x: cx + r * CGFloat(cos(baseAngle)),
                y: cy + r * CGFloat(sin(baseAngle))
            ))
            path.lineWidth = max(1.35, min(rect.width, rect.height) * 0.115)
            path.lineCapStyle = .round
            path.stroke()
        }

        let hub = NSBezierPath(ovalIn: NSRect(
            x: cx - inner * 1.05,
            y: cy - inner * 1.05,
            width: inner * 2.1,
            height: inner * 2.1
        ))
        color.setFill()
        hub.fill()
    }

    // ChatGPT: 6-fold interwoven hexagonal loop mark
    private static func drawOpenAIKnot(in rect: NSRect, color: NSColor) {
        let cx = rect.midX
        let cy = rect.midY
        let radius = min(rect.width, rect.height) * 0.29
        let offset = min(rect.width, rect.height) * 0.165
        let stroke = max(1.15, min(rect.width, rect.height) * 0.095)

        color.setStroke()
        for i in 0..<6 {
            let angle = Double(i) * (.pi / 3.0)
            let px = cx + offset * CGFloat(cos(angle))
            let py = cy + offset * CGFloat(sin(angle))
            let loopRect = NSRect(
                x: px - radius,
                y: py - radius * 0.72,
                width: radius * 2.0,
                height: radius * 1.44
            )
            var transform = AffineTransform.identity
            transform.translate(x: px, y: py)
            transform.rotate(byRadians: CGFloat(angle + .pi / 6.0))
            transform.translate(x: -px, y: -py)

            let path = NSBezierPath(roundedRect: loopRect, xRadius: radius * 0.7, yRadius: radius * 0.7)
            path.transform(using: transform)
            path.lineWidth = stroke
            path.stroke()
        }
    }

    // Antigravity: levitating 4-point star prism inside tilted orbital arc
    private static func drawAntigravityOrbit(in rect: NSRect, color: NSColor) {
        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) * 0.44

        let star = NSBezierPath()
        let waist = r * 0.22
        star.move(to: NSPoint(x: cx, y: cy + r))
        star.curve(
            to: NSPoint(x: cx + r * 0.88, y: cy),
            controlPoint1: NSPoint(x: cx + waist * 0.4, y: cy + waist),
            controlPoint2: NSPoint(x: cx + waist, y: cy + waist * 0.4)
        )
        star.curve(
            to: NSPoint(x: cx, y: cy - r),
            controlPoint1: NSPoint(x: cx + waist, y: cy - waist * 0.4),
            controlPoint2: NSPoint(x: cx + waist * 0.4, y: cy - waist)
        )
        star.curve(
            to: NSPoint(x: cx - r * 0.88, y: cy),
            controlPoint1: NSPoint(x: cx - waist * 0.4, y: cy - waist),
            controlPoint2: NSPoint(x: cx - waist, y: cy - waist * 0.4)
        )
        star.curve(
            to: NSPoint(x: cx, y: cy + r),
            controlPoint1: NSPoint(x: cx - waist, y: cy + waist * 0.4),
            controlPoint2: NSPoint(x: cx - waist * 0.4, y: cy + waist)
        )
        star.close()
        color.setFill()
        star.fill()

        let orbitRect = NSRect(
            x: cx - r * 1.08,
            y: cy - r * 0.42,
            width: r * 2.16,
            height: r * 0.84
        )
        let orbit = NSBezierPath(ovalIn: orbitRect)
        var tilt = AffineTransform.identity
        tilt.translate(x: cx, y: cy)
        tilt.rotate(byRadians: 0.42)
        tilt.translate(x: -cx, y: -cy)
        orbit.transform(using: tilt)
        orbit.lineWidth = max(1.05, min(rect.width, rect.height) * 0.08)
        color.withAlphaComponent(0.78).setStroke()
        orbit.stroke()
    }

    // DeepSeek: stylized whale silhouette with tail fluke
    private static func drawDeepSeekWhale(in rect: NSRect, color: NSColor) {
        let w = rect.width
        let h = rect.height
        let ox = rect.minX
        let oy = rect.minY

        let body = NSBezierPath()
        body.move(to: NSPoint(x: ox + w * 0.14, y: oy + h * 0.46))
        body.curve(
            to: NSPoint(x: ox + w * 0.68, y: oy + h * 0.82),
            controlPoint1: NSPoint(x: ox + w * 0.12, y: oy + h * 0.78),
            controlPoint2: NSPoint(x: ox + w * 0.42, y: oy + h * 0.88)
        )
        body.curve(
            to: NSPoint(x: ox + w * 0.84, y: oy + h * 0.56),
            controlPoint1: NSPoint(x: ox + w * 0.80, y: oy + h * 0.78),
            controlPoint2: NSPoint(x: ox + w * 0.86, y: oy + h * 0.66)
        )
        // Tail fluke
        body.line(to: NSPoint(x: ox + w * 0.96, y: oy + h * 0.70))
        body.line(to: NSPoint(x: ox + w * 0.90, y: oy + h * 0.48))
        body.line(to: NSPoint(x: ox + w * 0.97, y: oy + h * 0.28))
        body.line(to: NSPoint(x: ox + w * 0.78, y: oy + h * 0.36))
        // Belly curve
        body.curve(
            to: NSPoint(x: ox + w * 0.14, y: oy + h * 0.46),
            controlPoint1: NSPoint(x: ox + w * 0.56, y: oy + h * 0.16),
            controlPoint2: NSPoint(x: ox + w * 0.20, y: oy + h * 0.20)
        )
        body.close()

        color.setFill()
        body.fill()

        // Eye cutout
        let eyeSize = max(1.6, min(w, h) * 0.12)
        let eye = NSBezierPath(ovalIn: NSRect(
            x: ox + w * 0.30,
            y: oy + h * 0.52,
            width: eyeSize,
            height: eyeSize
        ))
        NSColor.windowBackgroundColor.setFill()
        eye.fill()
    }
}

public struct BrandBadgeView: View {
    public let provider: ProviderID
    public var size: CGFloat = 20
    public var iconMode: IconColorMode = .brand

    public init(provider: ProviderID, size: CGFloat = 20, iconMode: IconColorMode = .brand) {
        self.provider = provider
        self.size = size
        self.iconMode = iconMode
    }

    public var body: some View {
        Image(nsImage: BrandIconRenderer.statusIcon(for: provider, size: size, mode: iconMode))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
