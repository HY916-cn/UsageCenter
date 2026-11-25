import AppKit
import SwiftUI
import UsageCenterCore

enum CodexPalette {
    // High-contrast luminous colors — never black or dark-gray on Liquid Glass
    static let normalWhiteNS = NSColor.white
    static let timeBlueNS = NSColor(srgbRed: 0.34, green: 0.76, blue: 1.0, alpha: 1.0)
    static let warningYellowNS = NSColor(srgbRed: 1.0, green: 0.84, blue: 0.16, alpha: 1.0)
    static let criticalRedNS = NSColor(srgbRed: 1.0, green: 0.32, blue: 0.32, alpha: 1.0)

    static let normalWhite = Color.white
    static let timeBlue = Color(red: 0.34, green: 0.76, blue: 1.0)
    static let warningYellow = Color(red: 1.0, green: 0.84, blue: 0.16)
    static let criticalRed = Color(red: 1.0, green: 0.32, blue: 0.32)

    static let chartAccent = Color(red: 0.24, green: 0.75, blue: 0.84)
    static let chartAccentBright = Color(red: 0.38, green: 0.86, blue: 0.94)

    static func quotaColor(for level: QuotaAttentionLevel) -> Color {
        switch level {
        case .normal: return normalWhite
        case .warning: return warningYellow
        case .critical: return criticalRed
        }
    }

    static func quotaNSColor(for level: QuotaAttentionLevel) -> NSColor {
        switch level {
        case .normal: return normalWhiteNS
        case .warning: return warningYellowNS
        case .critical: return criticalRedNS
        }
    }
}

struct HistoryBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.06)
            RadialGradient(
                colors: [CodexPalette.chartAccent.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 620
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Native macOS 26/27 Liquid Glass card surface.
    func liquidGlassSurface(cornerRadius: CGFloat = 20, interactive: Bool = false) -> some View {
        self.glassEffect(
            interactive ? .regular.interactive() : .regular,
            in: .rect(cornerRadius: cornerRadius)
        )
    }

    /// Enforces crisp luminous dark Liquid Glass typography so black text/elements never appear.
    func applyDarkLiquidGlassTheme() -> some View {
        self
            .preferredColorScheme(.dark)
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
            .background(DarkAquaWindowBridge())
    }
}

struct DarkAquaWindowBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> BridgeView {
        BridgeView()
    }

    func updateNSView(_ nsView: BridgeView, context: Context) {
        nsView.apply()
    }

    final class BridgeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            window?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
