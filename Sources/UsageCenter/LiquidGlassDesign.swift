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

// MARK: - Custom Vector Chart Legend Swatches

enum ChartLegendKind {
    case actualCurve
    case idealPace
    case unrecordedGap
}

struct ChartLegendItem: View {
    let kind: ChartLegendKind
    let title: String
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 5 : 6) {
            swatchView
                .frame(width: compact ? 18 : 22, height: compact ? 10 : 12)
            Text(title)
                .font(compact ? .system(size: 10).monospacedDigit() : .caption)
                .foregroundStyle(labelColor)
        }
    }

    private var labelColor: Color {
        switch kind {
        case .actualCurve: return CodexPalette.chartAccentBright
        case .idealPace: return .white.opacity(0.78)
        case .unrecordedGap: return .white.opacity(0.68)
        }
    }

    @ViewBuilder
    private var swatchView: some View {
        switch kind {
        case .actualCurve:
            Canvas { ctx, size in
                let w = size.width
                let h = size.height

                var area = Path()
                area.move(to: CGPoint(x: 1, y: h - 1))
                area.addLine(to: CGPoint(x: 1, y: h * 0.72))
                area.addCurve(
                    to: CGPoint(x: w - 1, y: h * 0.24),
                    control1: CGPoint(x: w * 0.36, y: h * 0.76),
                    control2: CGPoint(x: w * 0.62, y: h * 0.22)
                )
                area.addLine(to: CGPoint(x: w - 1, y: h - 1))
                area.closeSubpath()
                ctx.fill(
                    area,
                    with: .linearGradient(
                        Gradient(colors: [CodexPalette.chartAccent.opacity(0.38), .clear]),
                        startPoint: CGPoint(x: w / 2, y: 0),
                        endPoint: CGPoint(x: w / 2, y: h)
                    )
                )

                var curve = Path()
                curve.move(to: CGPoint(x: 1, y: h * 0.72))
                curve.addCurve(
                    to: CGPoint(x: w - 1, y: h * 0.24),
                    control1: CGPoint(x: w * 0.36, y: h * 0.76),
                    control2: CGPoint(x: w * 0.62, y: h * 0.22)
                )
                ctx.stroke(
                    curve,
                    with: .color(CodexPalette.chartAccentBright),
                    style: StrokeStyle(lineWidth: 1.75, lineCap: .round)
                )

                let dotR: CGFloat = compact ? 2.1 : 2.5
                let dotCenter = CGPoint(x: w - 2.6, y: h * 0.26)
                let dotRect = CGRect(x: dotCenter.x - dotR, y: dotCenter.y - dotR, width: dotR * 2, height: dotR * 2)
                ctx.fill(Path(ellipseIn: dotRect), with: .color(CodexPalette.chartAccentBright))
            }

        case .idealPace:
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                var line = Path()
                line.move(to: CGPoint(x: 1, y: h * 0.26))
                line.addLine(to: CGPoint(x: w - 1, y: h * 0.76))
                ctx.stroke(
                    line,
                    with: .color(.white.opacity(0.75)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3.2, 2.8])
                )
            }

        case .unrecordedGap:
            Canvas { ctx, size in
                let rect = CGRect(x: 1, y: 1, width: size.width - 2, height: size.height - 2)
                let box = Path(roundedRect: rect, cornerRadius: 2.5)
                ctx.fill(box, with: .color(.white.opacity(0.11)))

                ctx.drawLayer { layer in
                    layer.clip(to: box)
                    var hatch = Path()
                    var x: CGFloat = -size.height
                    while x < size.width + size.height {
                        hatch.move(to: CGPoint(x: x, y: size.height))
                        hatch.addLine(to: CGPoint(x: x + size.height, y: 0))
                        x += 4.5
                    }
                    layer.stroke(hatch, with: .color(.white.opacity(0.26)), lineWidth: 1.0)
                }

                ctx.stroke(
                    box,
                    with: .color(.white.opacity(0.42)),
                    style: StrokeStyle(lineWidth: 0.9, dash: [2.5, 2.0])
                )
            }
        }
    }
}

// MARK: - Uniform Width & Flush-Aligned Liquid Glass Dropdown

struct DropdownChoice<Value: Hashable>: Identifiable {
    let id = UUID()
    let title: String
    let value: Value
}

struct UniformDropdown<Value: Hashable>: View {
    @Binding var selection: Value
    let choices: [DropdownChoice<Value>]
    var width: CGFloat = 212
    var height: CGFloat = 28

    private var currentTitle: String {
        choices.first(where: { $0.value == selection })?.title ?? ""
    }

    var body: some View {
        Menu {
            ForEach(choices) { choice in
                Button {
                    selection = choice.value
                } label: {
                    if choice.value == selection {
                        Label(choice.title, systemImage: "checkmark")
                    } else {
                        Text(choice.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentTitle)
                    .font(.system(size: height <= 25 ? 11.5 : 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 10)
            .frame(width: width, height: height)
            .background(
                Color.white.opacity(0.11),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(width: width, height: height)
    }
}
