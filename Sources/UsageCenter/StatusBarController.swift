import AppKit
import Combine
import SwiftUI
import UsageCenterCore

/// Pure white SVG + luminous high-contrast rendering in the menu bar.
enum StatusSegmentRenderer {
    static let barHeight: CGFloat = 22

    enum UnitSlotKind {
        case quota(showsDetailedTime: Bool)
        case balance
    }

    struct MetricUnit {
        let slotKind: UnitSlotKind
        let primaryText: String
        let captionText: String
        let quotaPercent: Double?
        let timePercent: Double?
        let attention: QuotaAttentionLevel
    }

    struct SegmentLayout {
        let units: [MetricUnit]
        let style: SegmentDisplayStyle
        let size: NSSize
        let isStale: Bool
    }

    private static let ringSize: CGFloat = 16.5
    private static let barWidth: CGFloat = 22.0
    private static let barHeightVal: CGFloat = 3.0
    private static let iconSize: CGFloat = 14.5
    private static let unitGap: CGFloat = 5.5
    private static let fixedQuotaTextWidth: CGFloat = 32.0
    private static let fixedQuotaDetailedTextWidth: CGFloat = 38.0
    private static let fixedCompactBarColumnWidth: CGFloat = 34.0
    private static let fixedBalanceTextWidth: CGFloat = 54.0

    static func buildLayout(
        config: ProviderSectionConfig,
        snapshot: ProviderSnapshot,
        preferences: UsageCenterPreferences,
        now: Date = Date()
    ) -> SegmentLayout {
        let style = preferences.effectiveStyle(for: config.provider)
        let showsDetailedTime = config.showsResetTimeInMenuBar && preferences.timeDisplayMode != .hidden
        let quotaSlotKind: UnitSlotKind = .quota(showsDetailedTime: showsDetailedTime)

        if preferences.developerPreviewEnabled {
            if config.provider == .deepseek {
                let unit = MetricUnit(slotKind: .balance, primaryText: "¥36.44", captionText: "余额", quotaPercent: 72, timePercent: nil, attention: .normal)
                let w = computeTotalWidth(units: [unit], style: .statsMini)
                return SegmentLayout(units: [unit], style: .statsMini, size: NSSize(width: w, height: barHeight), isStale: false)
            }
            let q = Int(preferences.developerPreviewRemaining.rounded())
            let t = preferences.developerPreviewTimeRemaining
            let att: QuotaAttentionLevel = q < 20 ? .critical : (Double(q) < t ? .warning : .normal)
            let u1 = MetricUnit(slotKind: quotaSlotKind, primaryText: "\(q)%", captionText: "5h", quotaPercent: Double(q), timePercent: t, attention: att)
            let u2 = MetricUnit(slotKind: quotaSlotKind, primaryText: "\(max(0, q - 8))%", captionText: "7d", quotaPercent: Double(max(0, q - 8)), timePercent: min(100, t + 15), attention: att)
            let units = (config.windowVisibility == .both) ? [u1, u2] : [u1]
            let w = computeTotalWidth(units: units, style: style)
            return SegmentLayout(units: units, style: style, size: NSSize(width: w, height: barHeight), isStale: false)
        }

        if config.provider == .deepseek {
            let mainText: String
            let attention: QuotaAttentionLevel
            if let bal = snapshot.preferredBalance(currencyPreference: preferences.deepSeekCurrencyPreference) {
                mainText = bal.formattedTotal
                let amount = bal.numericTotal
                attention = (snapshot.isAvailable == false || amount <= 1) ? .critical : (amount < 10 ? .warning : .normal)
            } else if snapshot.isLoading {
                mainText = "…"
                attention = .normal
            } else {
                mainText = "--"
                attention = .normal
            }

            let unit = MetricUnit(
                slotKind: .balance,
                primaryText: mainText,
                captionText: "余额",
                quotaPercent: nil,
                timePercent: nil,
                attention: attention
            )
            let width = computeTotalWidth(units: [unit], style: .statsMini)
            return SegmentLayout(
                units: [unit],
                style: .statsMini,
                size: NSSize(width: width, height: barHeight),
                isStale: snapshot.isStale
            )
        }

        let pair = snapshot.resolvedWindows(antigravityGroup: preferences.antigravityGroup)
        let tightest = snapshot.mostConstrainedWindow(antigravityGroup: preferences.antigravityGroup)
        let effectiveTimeMode: TimeDisplayMode = config.showsResetTimeInMenuBar ? preferences.timeDisplayMode : .hidden

        func makeUnit(window: QuotaWindow?, tag: String) -> MetricUnit {
            guard let window else {
                return MetricUnit(
                    slotKind: quotaSlotKind,
                    primaryText: snapshot.isLoading ? "…" : "--",
                    captionText: tag,
                    quotaPercent: nil,
                    timePercent: nil,
                    attention: .normal
                )
            }
            let pct = window.displayPercent(mode: preferences.percentMode)
            let remTime = window.remainingTimePercent(at: now)
            let timeVal = preferences.percentMode == .remaining ? remTime : remTime.map { 100.0 - $0 }

            let caption: String
            switch effectiveTimeMode {
            case .hidden:
                caption = tag
            case .countdown, .clock:
                caption = window.shortTimeLabel(at: now, mode: effectiveTimeMode) ?? tag
            }

            return MetricUnit(
                slotKind: quotaSlotKind,
                primaryText: "\(pct)%",
                captionText: caption,
                quotaPercent: Double(pct),
                timePercent: timeVal,
                attention: window.attentionLevel(at: now, criticalBelow: preferences.lowQuotaThreshold)
            )
        }

        let units: [MetricUnit]
        switch config.windowVisibility {
        case .both:
            units = [
                makeUnit(window: pair.fiveHour, tag: "5h"),
                makeUnit(window: pair.weekly, tag: "7d")
            ]
        case .mostConstrained:
            let tag = (tightest?.kind == .weekly) ? "7d" : "5h"
            units = [makeUnit(window: tightest, tag: tag)]
        case .fiveHourOnly:
            units = [makeUnit(window: pair.fiveHour, tag: "5h")]
        case .weeklyOnly:
            units = [makeUnit(window: pair.weekly, tag: "7d")]
        }

        let width = computeTotalWidth(units: units, style: style)
        return SegmentLayout(
            units: units,
            style: style,
            size: NSSize(width: width, height: barHeight),
            isStale: snapshot.isStale
        )
    }

    private static func primaryFont(monospaced: Bool) -> NSFont {
        monospaced
            ? .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
            : .systemFont(ofSize: 10.5, weight: .semibold)
    }

    private static let captionFont: NSFont = .monospacedDigitSystemFont(ofSize: 6.8, weight: .medium)

    /// Deterministic fixed column width per slot kind & style — never varies with live digit count.
    private static func unitWidth(_ unit: MetricUnit, style: SegmentDisplayStyle) -> CGFloat {
        let textW: CGFloat
        switch unit.slotKind {
        case .balance:
            textW = fixedBalanceTextWidth
        case .quota(let showsDetailedTime):
            textW = showsDetailedTime ? fixedQuotaDetailedTextWidth : fixedQuotaTextWidth
        }

        switch style {
        case .rings:
            return ringSize + 2.5 + textW
        case .horizontalBar, .dualBars:
            return barWidth + 3.0 + textW
        case .compactBar:
            if case .balance = unit.slotKind {
                return fixedBalanceTextWidth
            }
            return fixedCompactBarColumnWidth
        case .statsMini:
            return textW
        case .progressOnly:
            return ringSize
        }
    }

    private static func computeTotalWidth(units: [MetricUnit], style: SegmentDisplayStyle) -> CGFloat {
        let hPad: CGFloat = 9
        let iconAndGap: CGFloat = iconSize + 4.5
        let unitsSum = units.map { unitWidth($0, style: style) }.reduce(0, +)
        let gaps = CGFloat(max(0, units.count - 1)) * unitGap
        return ceil(hPad + iconAndGap + unitsSum + gaps)
    }

    static func drawSegment(
        in rect: NSRect,
        provider: ProviderID,
        layout: SegmentLayout,
        preferences: UsageCenterPreferences,
        isHovered: Bool,
        isSelected: Bool
    ) {
        if isHovered || isSelected {
            let highlight = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 1), xRadius: 5, yRadius: 5)
            NSColor.white.withAlphaComponent(isSelected ? 0.22 : 0.12).setFill()
            highlight.fill()
        }

        let midY = rect.midY
        var x = rect.minX + 4.5

        // Pure White Official SVG Icon
        let iconImg = BrandIconRenderer.whiteIcon(for: provider, size: iconSize)
        iconImg.draw(in: NSRect(x: x, y: midY - iconSize / 2, width: iconSize, height: iconSize))
        x += iconSize + 4.5

        let pFont = primaryFont(monospaced: preferences.monospacedDigits)
        let primaryTextColor: NSColor = layout.isStale
            ? NSColor.white.withAlphaComponent(0.68)
            : .white
        let captionTextColor: NSColor = NSColor.white.withAlphaComponent(0.76)

        for (idx, unit) in layout.units.enumerated() {
            let uWidth = unitWidth(unit, style: layout.style)
            let quotaColor = CodexPalette.quotaNSColor(for: unit.attention)

            switch layout.style {
            case .rings:
                let rRect = NSRect(x: x, y: midY - ringSize / 2, width: ringSize, height: ringSize)
                drawConcentricRings(
                    in: rRect,
                    quotaPercent: unit.quotaPercent,
                    timePercent: unit.timePercent,
                    quotaColor: quotaColor
                )
                let tx = x + ringSize + 2.5
                let tw = uWidth - ringSize - 2.5
                drawPercentageOverCaption(
                    primary: unit.primaryText,
                    caption: unit.captionText,
                    in: NSRect(x: tx, y: 0, width: tw, height: rect.height),
                    primaryFont: pFont,
                    primaryColor: primaryTextColor,
                    captionColor: captionTextColor
                )

            case .horizontalBar:
                let bRect = NSRect(x: x, y: midY - barHeightVal / 2, width: barWidth, height: barHeightVal)
                drawPillBar(in: bRect, percent: unit.quotaPercent, color: quotaColor)
                let tx = x + barWidth + 3.0
                let tw = uWidth - barWidth - 3.0
                drawPercentageOverCaption(
                    primary: unit.primaryText,
                    caption: unit.captionText,
                    in: NSRect(x: tx, y: 0, width: tw, height: rect.height),
                    primaryFont: pFont,
                    primaryColor: primaryTextColor,
                    captionColor: captionTextColor
                )

            case .dualBars:
                let totalBarsH = barHeightVal * 2 + 2.5
                let topBarRect = NSRect(x: x, y: midY + 1.25, width: barWidth, height: barHeightVal)
                let botBarRect = NSRect(x: x, y: midY - totalBarsH / 2, width: barWidth, height: barHeightVal)
                drawPillBar(in: topBarRect, percent: unit.quotaPercent, color: quotaColor)
                drawPillBar(in: botBarRect, percent: unit.timePercent, color: CodexPalette.timeBlueNS)

                let tx = x + barWidth + 3.0
                let tw = uWidth - barWidth - 3.0
                drawPercentageOverCaption(
                    primary: unit.primaryText,
                    caption: unit.captionText,
                    in: NSRect(x: tx, y: 0, width: tw, height: rect.height),
                    primaryFont: pFont,
                    primaryColor: primaryTextColor,
                    captionColor: captionTextColor
                )

            case .compactBar:
                let fixedBarW = uWidth - 2.0
                drawText(
                    unit.primaryText,
                    in: NSRect(x: x, y: 6.5, width: uWidth, height: 13),
                    font: pFont,
                    color: primaryTextColor,
                    alignment: .center
                )
                drawPillBar(
                    in: NSRect(x: x + 1.0, y: 2.0, width: fixedBarW, height: barHeightVal),
                    percent: unit.quotaPercent,
                    color: quotaColor
                )

            case .statsMini:
                drawPercentageOverCaption(
                    primary: unit.primaryText,
                    caption: unit.captionText,
                    in: NSRect(x: x, y: 0, width: uWidth, height: rect.height),
                    primaryFont: pFont,
                    primaryColor: primaryTextColor,
                    captionColor: captionTextColor
                )

            case .progressOnly:
                let rRect = NSRect(x: x, y: midY - ringSize / 2, width: ringSize, height: ringSize)
                drawConcentricRings(
                    in: rRect,
                    quotaPercent: unit.quotaPercent,
                    timePercent: unit.timePercent,
                    quotaColor: quotaColor
                )
            }

            x += uWidth
            if idx < layout.units.count - 1 {
                x += unitGap
            }
        }
    }

    private static func drawPercentageOverCaption(
        primary: String,
        caption: String,
        in rect: NSRect,
        primaryFont: NSFont,
        primaryColor: NSColor,
        captionColor: NSColor
    ) {
        drawText(
            primary,
            in: NSRect(x: rect.minX, y: rect.height - 12.8, width: rect.width, height: 12.2),
            font: primaryFont,
            color: primaryColor,
            alignment: .center
        )
        drawText(
            caption,
            in: NSRect(x: rect.minX, y: 0.6, width: rect.width, height: 8.4),
            font: captionFont,
            color: captionColor,
            alignment: .center
        )
    }

    private static func drawConcentricRings(
        in rect: NSRect,
        quotaPercent: Double?,
        timePercent: Double?,
        quotaColor: NSColor
    ) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let outerWidth: CGFloat = 2.6
        let innerWidth: CGFloat = 1.8
        let outerRadius = max(1, min(rect.width, rect.height) / 2 - outerWidth / 2)
        let innerRadius = max(1, outerRadius - outerWidth / 2 - 0.35 - innerWidth / 2)

        drawArc(
            center: center,
            radius: outerRadius,
            lineWidth: outerWidth,
            percent: nil,
            color: NSColor.white.withAlphaComponent(0.24)
        )
        guard let quotaPercent else {
            drawText(
                "?",
                in: NSRect(x: rect.minX, y: rect.midY - 5, width: rect.width, height: 10),
                font: .systemFont(ofSize: 8, weight: .semibold),
                color: NSColor.white.withAlphaComponent(0.75),
                alignment: .center
            )
            return
        }
        drawArc(
            center: center,
            radius: outerRadius,
            lineWidth: outerWidth,
            percent: quotaPercent,
            color: quotaColor
        )

        guard let timePercent else { return }
        drawArc(
            center: center,
            radius: innerRadius,
            lineWidth: innerWidth,
            percent: nil,
            color: CodexPalette.timeBlueNS.withAlphaComponent(0.26)
        )
        drawArc(
            center: center,
            radius: innerRadius,
            lineWidth: innerWidth,
            percent: timePercent,
            color: CodexPalette.timeBlueNS
        )
    }

    private static func drawArc(
        center: NSPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        percent: Double?,
        color: NSColor
    ) {
        let path = NSBezierPath()
        if let percent {
            let fraction = CGFloat(min(100, max(0, percent))) / 100.0
            guard fraction > 0.005 else { return }
            path.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - 360 * fraction,
                clockwise: true
            )
            path.lineCapStyle = .round
        } else {
            path.appendOval(in: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }

    private static func drawPillBar(in rect: NSRect, percent: Double?, color: NSColor) {
        let r = rect.height / 2
        let track = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        NSColor.white.withAlphaComponent(0.24).setFill()
        track.fill()

        guard let percent else { return }
        let fraction = CGFloat(min(100, max(0, percent))) / 100.0
        guard fraction > 0.005 else { return }
        let fillRect = NSRect(
            x: rect.minX,
            y: rect.minY,
            width: max(rect.height, rect.width * fraction),
            height: rect.height
        )
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: r, yRadius: r)
        color.setFill()
        fill.fill()
    }

    private static func drawText(
        _ value: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping
        (value as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }

    static func renderCompositePreviewImage(
        preferences: UsageCenterPreferences,
        snapshots: [ProviderID: ProviderSnapshot]
    ) -> NSImage {
        let enabled = preferences.enabledSections
        guard !enabled.isEmpty else {
            return NSImage(size: NSSize(width: 100, height: barHeight), flipped: false) { rect in
                drawText("未启用分段", in: rect.insetBy(dx: 6, dy: 4), font: .systemFont(ofSize: 11), color: .white, alignment: .center)
                return true
            }
        }

        let now = Date()
        let items: [(ProviderSectionConfig, SegmentLayout)] = enabled.map { cfg in
            let snap = snapshots[cfg.provider] ?? ProviderSnapshot(provider: cfg.provider)
            return (cfg, buildLayout(config: cfg, snapshot: snap, preferences: preferences, now: now))
        }

        let gapWidth: CGFloat = preferences.showsDividers ? 9 : 4
        let totalWidth = items.map(\.1.size.width).reduce(0, +)
            + CGFloat(max(0, items.count - 1)) * gapWidth + 4

        let img = NSImage(size: NSSize(width: totalWidth, height: barHeight), flipped: false) { _ in
            var x: CGFloat = 2
            for (idx, item) in items.enumerated() {
                let segRect = NSRect(x: x, y: 0, width: item.1.size.width, height: barHeight)
                drawSegment(
                    in: segRect,
                    provider: item.0.provider,
                    layout: item.1,
                    preferences: preferences,
                    isHovered: false,
                    isSelected: false
                )
                x += item.1.size.width
                if idx < items.count - 1 {
                    if preferences.showsDividers {
                        let lineX = floor(x + gapWidth / 2) + 0.5
                        let line = NSBezierPath()
                        line.move(to: NSPoint(x: lineX, y: 4.5))
                        line.line(to: NSPoint(x: lineX, y: barHeight - 4.5))
                        line.lineWidth = 1
                        NSColor.white.withAlphaComponent(0.28).setStroke()
                        line.stroke()
                    }
                    x += gapWidth
                }
            }
            return true
        }
        img.isTemplate = false
        return img
    }
}

// MARK: - Coordinate-Exact Composite Status Bar View

final class CompositeStatusBarView: NSView {
    struct Slot {
        let provider: ProviderID
        let layout: StatusSegmentRenderer.SegmentLayout
        let frame: NSRect
    }

    private(set) var slots: [Slot] = []
    private var preferences = UsageCenterPreferences()
    private var hoveredProvider: ProviderID?
    private var selectedProvider: ProviderID?
    private var trackingRef: NSTrackingArea?

    // Let NSStatusBarButton handle all click events cleanly via target/action
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(
        preferences: UsageCenterPreferences,
        snapshots: [ProviderID: ProviderSnapshot],
        selectedProvider: ProviderID?
    ) -> CGFloat {
        self.preferences = preferences
        self.selectedProvider = selectedProvider
        let enabled = preferences.enabledSections
        let now = Date()

        guard !enabled.isEmpty else {
            slots = []
            let fallback: CGFloat = 28
            setFrameSize(NSSize(width: fallback, height: StatusSegmentRenderer.barHeight))
            needsDisplay = true
            return fallback
        }

        let gapWidth: CGFloat = preferences.showsDividers ? 9 : 4
        var cursorX: CGFloat = 2
        var built: [Slot] = []

        for (idx, cfg) in enabled.enumerated() {
            let snap = snapshots[cfg.provider] ?? ProviderSnapshot(provider: cfg.provider)
            let layout = StatusSegmentRenderer.buildLayout(
                config: cfg,
                snapshot: snap,
                preferences: preferences,
                now: now
            )
            let rect = NSRect(x: cursorX, y: 0, width: layout.size.width, height: StatusSegmentRenderer.barHeight)
            built.append(Slot(provider: cfg.provider, layout: layout, frame: rect))
            cursorX += layout.size.width
            if idx < enabled.count - 1 {
                cursorX += gapWidth
            }
        }
        cursorX += 2

        slots = built
        setFrameSize(NSSize(width: cursorX, height: StatusSegmentRenderer.barHeight))
        needsDisplay = true
        return cursorX
    }

    /// Resolves the exact clicked slot using horizontal X coordinate in this view's space.
    func resolveSlot(atLocalX x: CGFloat) -> Slot? {
        guard !slots.isEmpty else { return nil }
        if let exact = slots.first(where: { x >= $0.frame.minX && x <= $0.frame.maxX }) {
            return exact
        }
        return slots.min(by: { abs($0.frame.midX - x) < abs($1.frame.midX - x) })
    }

    func slot(for provider: ProviderID) -> Slot? {
        slots.first { $0.provider == provider }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingRef {
            removeTrackingArea(trackingRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingRef = area
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let hit = resolveSlot(atLocalX: pt.x)?.provider
        if hit != hoveredProvider {
            hoveredProvider = hit
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredProvider != nil {
            hoveredProvider = nil
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !slots.isEmpty else {
            let r = NSRect(x: bounds.midX - 7.5, y: bounds.midY - 7.5, width: 15, height: 15)
            BrandIconRenderer.appMarkWhite(size: 15).draw(in: r)
            return
        }

        let gapWidth: CGFloat = preferences.showsDividers ? 9 : 4
        for (idx, slot) in slots.enumerated() {
            StatusSegmentRenderer.drawSegment(
                in: slot.frame,
                provider: slot.provider,
                layout: slot.layout,
                preferences: preferences,
                isHovered: hoveredProvider == slot.provider,
                isSelected: selectedProvider == slot.provider
            )
            if preferences.showsDividers, idx < slots.count - 1 {
                let lineX = floor(slot.frame.maxX + gapWidth / 2) + 0.5
                let line = NSBezierPath()
                line.move(to: NSPoint(x: lineX, y: 4.5))
                line.line(to: NSPoint(x: lineX, y: bounds.height - 4.5))
                line.lineWidth = 1
                NSColor.white.withAlphaComponent(0.28).setStroke()
                line.stroke()
            }
        }
    }
}

// MARK: - Native macOS 27 NSGlassEffectView Unscrolled Floating Popup Panel

@MainActor
final class LiquidGlassPopupPanel: NSPanel {
    private static let cornerRadius: CGFloat = 20
    private static let horizontalShadowPad: CGFloat = 18
    private static let bottomShadowPad: CGFloat = 22
    private static let topShadowPad: CGFloat = 6

    private let outerContainer = NSView()
    private let shadowCasterLayer = CALayer()
    private let shadowCutoutMask = CAShapeLayer()
    private let glassContainer = NSGlassEffectView()
    private var hostingView: NSHostingView<ProviderDetailPopoverView>?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 416, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        // Disable WindowServer's rectangular/.darkAqua 1px black border rim;
        // render a clean masked continuous-squircle shadow outside glassContainer instead.
        self.hasShadow = false
        self.level = .statusBar
        self.collectionBehavior = [.transient, .moveToActiveSpace, .ignoresCycle]
        self.hidesOnDeactivate = false
        self.appearance = NSAppearance(named: .darkAqua)

        outerContainer.wantsLayer = true
        outerContainer.layer?.backgroundColor = NSColor.clear.cgColor
        outerContainer.layer?.masksToBounds = false

        shadowCasterLayer.backgroundColor = NSColor.clear.cgColor
        shadowCasterLayer.shadowColor = NSColor.black.cgColor
        shadowCasterLayer.shadowOpacity = 0.28
        shadowCasterLayer.shadowRadius = 11
        shadowCasterLayer.shadowOffset = CGSize(width: 0, height: -4)
        shadowCutoutMask.fillRule = .evenOdd
        shadowCasterLayer.mask = shadowCutoutMask
        outerContainer.layer?.addSublayer(shadowCasterLayer)

        glassContainer.cornerRadius = Self.cornerRadius
        glassContainer.style = .regular
        glassContainer.appearance = NSAppearance(named: .darkAqua)
        outerContainer.addSubview(glassContainer)

        self.contentView = outerContainer
    }

    override var canBecomeKey: Bool { true }

    var cardScreenRect: NSRect {
        let local = glassContainer.frame
        return convertToScreen(local)
    }

    func present(
        rootView: ProviderDetailPopoverView,
        belowScreenRect anchorRect: NSRect
    ) {
        let host: NSHostingView<ProviderDetailPopoverView>
        if let existing = hostingView {
            existing.rootView = rootView
            host = existing
        } else {
            let created = NSHostingView(rootView: rootView)
            created.sizingOptions = [.intrinsicContentSize]
            created.wantsLayer = true
            created.layer?.backgroundColor = NSColor.clear.cgColor
            created.layer?.cornerRadius = Self.cornerRadius
            created.layer?.cornerCurve = .continuous
            created.layer?.masksToBounds = true
            glassContainer.contentView = created
            hostingView = created
            host = created
        }

        layoutAndPosition(host: host, belowScreenRect: anchorRect, forceApply: true)
        makeKeyAndOrderFront(nil)
    }

    func resizeToFitCurrentContent(belowScreenRect anchorRect: NSRect) {
        guard isVisible, let host = hostingView else { return }
        layoutAndPosition(host: host, belowScreenRect: anchorRect, forceApply: false)
    }

    private func layoutAndPosition(
        host: NSHostingView<ProviderDetailPopoverView>,
        belowScreenRect anchorRect: NSRect,
        forceApply: Bool
    ) {
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        let cardWidth: CGFloat = max(384, ceil(fitting.width))
        let cardHeight: CGFloat = max(180, ceil(fitting.height))

        let panelWidth = cardWidth + Self.horizontalShadowPad * 2
        let panelHeight = cardHeight + Self.bottomShadowPad + Self.topShadowPad

        if !forceApply,
           abs(frame.height - panelHeight) <= 1,
           abs(frame.width - panelWidth) <= 1,
           abs(frame.midX - anchorRect.midX) <= 2 {
            return
        }

        let screen = NSScreen.screens.first { $0.frame.intersects(anchorRect) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var cardOriginX = round(anchorRect.midX - cardWidth / 2)
        cardOriginX = min(max(visibleFrame.minX + 8, cardOriginX), visibleFrame.maxX - cardWidth - 8)
        let panelOriginX = cardOriginX - Self.horizontalShadowPad
        let panelOriginY = round(anchorRect.minY - panelHeight)

        let targetFrame = NSRect(x: panelOriginX, y: panelOriginY, width: panelWidth, height: panelHeight)
        let cardFrame = NSRect(
            x: Self.horizontalShadowPad,
            y: Self.bottomShadowPad,
            width: cardWidth,
            height: cardHeight
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outerContainer.frame = NSRect(origin: .zero, size: targetFrame.size)
        glassContainer.frame = cardFrame
        host.frame = glassContainer.bounds

        shadowCasterLayer.frame = outerContainer.bounds
        let cardSquircle = NSBezierPath(
            roundedRect: cardFrame,
            xRadius: Self.cornerRadius,
            yRadius: Self.cornerRadius
        )
        shadowCasterLayer.shadowPath = cardSquircle.cgPath

        let cutout = CGMutablePath()
        cutout.addRect(outerContainer.bounds)
        cutout.addPath(cardSquircle.cgPath)
        shadowCutoutMask.frame = outerContainer.bounds
        shadowCutoutMask.path = cutout
        CATransaction.commit()

        setFrame(targetFrame, display: true)
    }
}

// MARK: - StatusBarController

@MainActor
final class StatusBarController: NSObject {
    private let store: UsageCenterStore
    private let onOpenSettings: () -> Void
    private let onOpenHistory: (ProviderID) -> Void
    private let statusItem: NSStatusItem
    private let compositeView = CompositeStatusBarView(frame: NSRect(x: 0, y: 0, width: 120, height: StatusSegmentRenderer.barHeight))
    private let popupPanel = LiquidGlassPopupPanel()
    private var openedProvider: ProviderID?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var tickTimer: Timer?

    init(
        store: UsageCenterStore,
        onOpenSettings: @escaping () -> Void,
        onOpenHistory: @escaping (ProviderID) -> Void
    ) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        self.onOpenHistory = onOpenHistory
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        setupStatusItem()
        bindStore()
        startMinuteTimer()
    }

    private func setupStatusItem() {
        statusItem.autosaveName = "UsageCenterUnifiedStatusItem"
        guard let button = statusItem.button else { return }
        button.image = NSImage()
        button.title = ""
        button.target = self
        button.action = #selector(handleStatusButtonAction(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])

        compositeView.frame = NSRect(x: 0, y: 0, width: 120, height: StatusSegmentRenderer.barHeight)
        button.addSubview(compositeView)

        rebuildBar()
    }

    private func bindStore() {
        store.$preferences
            .combineLatest(store.$snapshots)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.rebuildBar()
                if let opened = self.openedProvider,
                   self.popupPanel.isVisible,
                   let anchorRect = self.screenRect(for: opened) {
                    self.popupPanel.resizeToFitCurrentContent(belowScreenRect: anchorRect)
                }
            }
            .store(in: &cancellables)
    }

    private func startMinuteTimer() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildBar()
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func rebuildBar() {
        let width = compositeView.update(
            preferences: store.preferences,
            snapshots: store.snapshots,
            selectedProvider: popupPanel.isVisible ? openedProvider : nil
        )
        statusItem.length = width
        if let button = statusItem.button {
            let yOffset = floor((button.bounds.height - StatusSegmentRenderer.barHeight) / 2)
            compositeView.setFrameOrigin(NSPoint(x: 0, y: max(0, yOffset)))
        }
    }

    @objc private func handleStatusButtonAction(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
            presentContextMenu(with: event, for: sender)
            return
        }

        guard let win = sender.window else { return }
        // Convert exact screen cursor coordinate into CompositeStatusBarView local X
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = win.convertPoint(fromScreen: screenPoint)
        let localPoint = compositeView.convert(windowPoint, from: nil)

        guard let clickedSlot = compositeView.resolveSlot(atLocalX: localPoint.x) else {
            return
        }
        toggleSegmentPopup(for: clickedSlot.provider)
    }

    private func screenRect(for provider: ProviderID) -> NSRect? {
        guard let button = statusItem.button,
              let win = button.window,
              let slot = compositeView.slot(for: provider) else {
            return nil
        }
        let rectInWin = compositeView.convert(slot.frame, to: nil)
        return win.convertToScreen(rectInWin)
    }

    private func toggleSegmentPopup(for provider: ProviderID) {
        if popupPanel.isVisible, openedProvider == provider {
            closePopup()
            return
        }

        openedProvider = provider
        store.activeProvider = provider
        store.setPopoverVisible(true)
        rebuildBar()

        guard let anchorRect = screenRect(for: provider) else { return }

        let detailView = ProviderDetailPopoverView(
            store: store,
            onOpenSettings: { [weak self] in
                self?.closePopup()
                self?.onOpenSettings()
            },
            onOpenHistory: { [weak self] targetProvider in
                self?.closePopup()
                self?.onOpenHistory(targetProvider)
            }
        )
        popupPanel.present(rootView: detailView, belowScreenRect: anchorRect)
        installDismissMonitors()
    }

    func closePopup() {
        removeDismissMonitors()
        if popupPanel.isVisible {
            popupPanel.orderOut(nil)
        }
        openedProvider = nil
        store.setPopoverVisible(false)
        rebuildBar()
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.popupPanel.isVisible else { return }
                let mouse = NSEvent.mouseLocation
                if self.popupPanel.cardScreenRect.contains(mouse) { return }
                if let btn = self.statusItem.button,
                   let win = btn.window,
                   win.convertToScreen(btn.convert(btn.bounds, to: nil)).contains(mouse) {
                    return
                }
                self.closePopup()
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.closePopup()
                return nil
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func presentContextMenu(with event: NSEvent, for button: NSStatusBarButton) {
        closePopup()
        let menu = NSMenu()
        let refreshItem = NSMenuItem(title: "刷新全部", action: #selector(triggerRefreshAll), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let historyItem = NSMenuItem(title: "用量历史…", action: #selector(triggerOpenHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(triggerOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(triggerQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func triggerRefreshAll() {
        Task { await store.refreshAll() }
    }

    @objc private func triggerOpenHistory() {
        onOpenHistory(store.activeProvider)
    }

    @objc private func triggerOpenSettings() {
        onOpenSettings()
    }

    @objc private func triggerQuit() {
        NSApplication.shared.terminate(nil)
    }
}
