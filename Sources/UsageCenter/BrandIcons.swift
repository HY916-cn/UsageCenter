import AppKit
import SwiftUI
import UsageCenterCore

public enum BrandIconRenderer {
    private static var baseSVGCache: [ProviderID: NSImage] = [:]
    private static let cacheLock = NSLock()

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
