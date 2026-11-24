import AppKit
import SwiftUI
import UsageCenterCore

struct LiquidBackdrop: View {
    let accent: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark
                ? Color(red: 0.055, green: 0.060, blue: 0.075)
                : Color(nsColor: .windowBackgroundColor))

            RadialGradient(
                colors: [
                    accent.opacity(colorScheme == .dark ? 0.22 : 0.13),
                    accent.opacity(colorScheme == .dark ? 0.05 : 0.03),
                    .clear
                ],
                center: .topLeading,
                startRadius: 8,
                endRadius: 460
            )

            RadialGradient(
                colors: [
                    Color.cyan.opacity(colorScheme == .dark ? 0.10 : 0.06),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 12,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }
}

struct LiquidGlassStage<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

extension View {
    @ViewBuilder
    func liquidGlassCard(cornerRadius: CGFloat = 18, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 0.8)
                }
        }
    }

    @ViewBuilder
    func liquidGlassCapsule(interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: .capsule
            )
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 0.8)
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

struct ModernWindowChromeConfigurator: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> ChromeView {
        ChromeView(title: title)
    }

    func updateNSView(_ nsView: ChromeView, context: Context) {
        nsView.configure(title: title)
    }

    final class ChromeView: NSView {
        private var titleText: String

        init(title: String) {
            self.titleText = title
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

        func configure(title: String) {
            self.titleText = title
            apply()
        }

        private func apply() {
            guard let window else { return }
            window.title = titleText
            window.titlebarAppearsTransparent = true
            window.styleMask.insert([.fullSizeContentView, .resizable])
        }
    }
}
