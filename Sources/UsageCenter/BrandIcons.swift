import AppKit
import SwiftUI
import UsageCenterCore

public enum BrandIconRenderer {
    private static var baseSVGCache: [ProviderID: NSImage] = [:]
    private static var cachedAppIcon: NSImage?
    private static let cacheLock = NSLock()

    /// Loads UsageCenter's bundled AppIcon.icns.
    public static func appIconImage() -> NSImage {
        cacheLock.lock()
        if let existing = cachedAppIcon {
            cacheLock.unlock()
            return existing
        }
        cacheLock.unlock()

        let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
        let loaded = url.flatMap { NSImage(contentsOf: $0) }
            ?? NSApplication.shared.applicationIconImage
            ?? appMarkWhite(size: 64)

        cacheLock.lock()
        cachedAppIcon = loaded
        cacheLock.unlock()
        return loaded
    }

    /// Pure white monochrome UsageCenter 4-bar emblem for status bar fallback.
    public static func appMarkWhite(size: CGFloat = 15) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let barW = size * 0.145
            let gap = size * 0.075
            let totalW = barW * 4 + gap * 3
            let startX = rect.midX - totalW / 2
            let maxH = size * 0.76
            let baseY = rect.midY - maxH / 2
            let heights: [CGFloat] = [0.74, 0.96, 0.52, 0.84]

            NSColor.white.setFill()
            for (i, frac) in heights.enumerated() {
                let x = startX + CGFloat(i) * (barW + gap)
                let h = max(barW, maxH * frac)
                let r = NSRect(x: x, y: baseY, width: barW, height: h)
                NSBezierPath(roundedRect: r, xRadius: barW / 2, yRadius: barW / 2).fill()
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    /// Renders pure white (#FFFFFF) official SVG vector mark at crisp Retina resolution.
    public static func whiteIcon(for provider: ProviderID, size: CGFloat = 15) -> NSImage {
        guard let source = loadSVGImage(for: provider) else {
            return NSImage(size: NSSize(width: size, height: size))
        }

        let targetSize = NSSize(width: size, height: size)
        let rendered = NSImage(size: targetSize, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            source.draw(
                in: rect,
                from: NSRect(origin: .zero, size: source.size),
                operation: .sourceOver,
                fraction: 1.0
            )
            // Enforce crisp pure white tint across all pixels regardless of SVG parser defaults
            NSColor.white.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        rendered.isTemplate = false
        return rendered
    }

    private static func loadSVGImage(for provider: ProviderID) -> NSImage? {
        cacheLock.lock()
        if let cached = baseSVGCache[provider] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let fileName = svgFileName(for: provider)
        guard let url = locateSVGURL(named: fileName),
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        cacheLock.lock()
        baseSVGCache[provider] = image
        cacheLock.unlock()
        return image
    }

    private static func svgFileName(for provider: ProviderID) -> String {
        switch provider {
        case .claude: return "claude"
        case .chatgpt: return "chatgpt"
        case .antigravity: return "antigravity"
        case .deepseek: return "deepseek"
        }
    }

    private static func locateSVGURL(named name: String) -> URL? {
        if let mainURL = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Icons") {
            return mainURL
        }
        if let mainRootURL = Bundle.main.url(forResource: name, withExtension: "svg") {
            return mainRootURL
        }
        if let moduleURL = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "Icons") {
            return moduleURL
        }
        if let moduleRootURL = Bundle.module.url(forResource: name, withExtension: "svg") {
            return moduleRootURL
        }
        return nil
    }
}

public struct BrandBadgeView: View {
    public let provider: ProviderID
    public var size: CGFloat = 16

    public init(provider: ProviderID, size: CGFloat = 16) {
        self.provider = provider
        self.size = size
    }

    public var body: some View {
        Image(nsImage: BrandIconRenderer.whiteIcon(for: provider, size: size))
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

public struct UsageCenterAppIconView: View {
    public var size: CGFloat = 24

    public init(size: CGFloat = 24) {
        self.size = size
    }

    public var body: some View {
        Image(nsImage: BrandIconRenderer.appIconImage())
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
