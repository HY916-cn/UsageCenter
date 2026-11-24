import AppKit
import SwiftUI
import UsageCenterCore

public enum BrandIconRenderer {
    private static var baseSVGCache: [ProviderID: NSImage] = [:]
    private static let cacheLock = NSLock()

    public static func statusIcon(
        for provider: ProviderID,
        size: CGFloat = 15,
        mode: IconColorMode = .brand
    ) -> NSImage {
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
            return true
        }
        rendered.isTemplate = (mode == .monochrome)
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
        // 1. Packaged .app bundle Resources/Icons/
        if let mainURL = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Icons") {
            return mainURL
        }
        if let mainRootURL = Bundle.main.url(forResource: name, withExtension: "svg") {
            return mainRootURL
        }
        // 2. SwiftPM Bundle.module Resources/Icons/
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
    public var size: CGFloat = 18
    public var iconMode: IconColorMode = .brand

    public init(provider: ProviderID, size: CGFloat = 18, iconMode: IconColorMode = .brand) {
        self.provider = provider
        self.size = size
        self.iconMode = iconMode
    }

    public var body: some View {
        let img = BrandIconRenderer.statusIcon(for: provider, size: size, mode: iconMode)
        if iconMode == .monochrome {
            Image(nsImage: img)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(nsImage: img)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }
}
