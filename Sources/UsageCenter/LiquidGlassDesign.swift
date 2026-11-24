import AppKit
import SwiftUI
import UsageCenterCore

enum CodexPalette {
    static let timeBlueNS = NSColor(srgbRed: 0.30, green: 0.72, blue: 1.0, alpha: 1.0)
    static let warningYellowNS = NSColor.systemYellow
    static let criticalRedNS = NSColor.systemRed

    static let chartAccent = Color(red: 0.22, green: 0.72, blue: 0.79)
    static let chartAccentBright = Color(red: 0.33, green: 0.82, blue: 0.88)

    static func quotaSwiftUIColor(for level: QuotaAttentionLevel, colorScheme: ColorScheme) -> Color {
        let nsColor: NSColor = switch level {
        case .normal: .labelColor
        case .warning: warningYellowNS
        case .critical: criticalRedNS
        }
        return resolvedColor(nsColor, for: colorScheme)
    }

    static func timeSwiftUIColor(for colorScheme: ColorScheme) -> Color {
        resolvedColor(timeBlueNS, for: colorScheme)
    }

    private static func resolvedColor(_ nsColor: NSColor, for scheme: ColorScheme) -> Color {
        let name: NSAppearance.Name = scheme == .dark ? .darkAqua : .aqua
        guard let appearance = NSAppearance(named: name) else {
            return Color(nsColor: nsColor)
        }
        var resolved = nsColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = nsColor.usingColorSpace(.sRGB) ?? nsColor
        }
        return Color(nsColor: resolved)
    }
}

struct HistoryBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color(nsColor: .windowBackgroundColor))
            RadialGradient(
                colors: [CodexPalette.chartAccent.opacity(colorScheme == .dark ? 0.16 : 0.10), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 620
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    @ViewBuilder
    func liquidHistoryCard(cornerRadius: CGFloat = 22) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                }
        }
    }

    func applyAppearancePreference(_ pref: AppAppearancePreference) -> some View {
        let scheme: ColorScheme? = switch pref {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
        return self
            .preferredColorScheme(scheme)
            .background(WindowAppearanceBridge(preference: pref))
    }
}

struct WindowAppearanceBridge: NSViewRepresentable {
    let preference: AppAppearancePreference

    func makeNSView(context: Context) -> BridgeView {
        BridgeView(preference: preference)
    }

    func updateNSView(_ nsView: BridgeView, context: Context) {
        nsView.update(preference: preference)
    }

    final class BridgeView: NSView {
        private var preference: AppAppearancePreference

        init(preference: AppAppearancePreference) {
            self.preference = preference
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func update(preference: AppAppearancePreference) {
            self.preference = preference
            apply()
        }

        private func apply() {
            switch preference {
            case .system:
                window?.appearance = nil
            case .light:
                window?.appearance = NSAppearance(named: .aqua)
            case .dark:
                window?.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }
}
