import AppKit
import Combine
import SwiftUI
import UsageCenterCore

enum StatusSegmentRenderer {
    static let barHeight: CGFloat = 22

    struct MetricUnit {
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

    private static let ringSize: CGFloat = 17.0
    private static let barWidth: CGFloat = 24.0
    private static let barHeightVal: CGFloat = 3.0
    private static let iconSize: CGFloat = 15.0
    private static let unitGap: CGFloat = 6.0

    static func buildLayout(
        config: ProviderSectionConfig,
        snapshot: ProviderSnapshot,
        preferences: UsageCenterPreferences,
        now: Date = Date()
    ) -> SegmentLayout {
        let style = preferences.effectiveStyle(for: config.provider)

        // Developer Preview Override
        if preferences.developerPreviewEnabled {
            if config.provider == .deepseek {
                let unit = MetricUnit(
                    primaryText: "¥36.44",
                    captionText: "余额",
                    quotaPercent: 72,
                    timePercent: nil,
                    attention: .normal
                )
                let w = computeTotalWidth(units: [unit], style: .statsMini, monospaced: preferences.monospacedDigits)
                return SegmentLayout(units: [unit], style: .statsMini, size: NSSize(width: w, height: barHeight), isStale: false)
            }
            let q = Int(preferences.developerPreviewRemaining.rounded())
            let t = preferences.developerPreviewTimeRemaining
            let att: QuotaAttentionLevel = q < 20 ? .critical : (Double(q) < t ? .warning : .normal)
            let u1 = MetricUnit(primaryText: "\(q)%", captionText: "5h·3h", quotaPercent: Double(q), timePercent: t, attention: att)
            let u2 = MetricUnit(primaryText: "\(max(0, q - 8))%", captionText: "周·5d", quotaPercent: Double(max(0, q - 8)), timePercent: min(100, t + 15), attention: att)
            let units = (config.windowVisibility == .both) ? [u1, u2] : [u1]
            let w = computeTotalWidth(units: units, style: style, monospaced: preferences.monospacedDigits)
            return SegmentLayout(units: units, style: style, size: NSSize(width: w, height: barHeight), isStale: false)
        }

        if config.provider == .deepseek {
            let mainText: String
            let caption: String = config.showsProviderLabel ? "DSH" : "余额"
            let attention: QuotaAttentionLevel
            let progress: Double?

            if let bal = snapshot.preferredBalance(currencyPreference: preferences.deepSeekCurrencyPreference) {
                mainText = bal.formattedTotal
                let amount = bal.numericTotal
                progress = min(100, max(6, amount))
                attention = (snapshot.isAvailable == false || amount <= 1) ? .critical : (amount < 10 ? .warning : .normal)
            } else if snapshot.isLoading {
                mainText = "…"
                progress = nil
                attention = .normal
            } else {
                mainText = "--"
                progress = nil
                attention = .normal
            }

            let unit = MetricUnit(
                primaryText: mainText,
                captionText: caption,
                quotaPercent: progress,
                timePercent: nil,
                attention: attention
            )
            let width = computeTotalWidth(units: [unit], style: .statsMini, monospaced: preferences.monospacedDigits)
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
            if let shortTime = window.shortTimeLabel(at: now, mode: effectiveTimeMode) {
                caption = "\(tag)·\(shortTime)"
            } else {
                caption = tag
            }

            return MetricUnit(
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
                makeUnit(window: pair.weekly, tag: "周")
            ]
        case .mostConstrained:
            let tag = (tightest?.kind == .weekly) ? "周" : "5h"
            units = [makeUnit(window: tightest, tag: config.showsProviderLabel ? config.provider.shortLabel : tag)]
        case .fiveHourOnly:
            units = [makeUnit(window: pair.fiveHour, tag: "5h")]
        case .weeklyOnly:
            units = [makeUnit(window: pair.weekly, tag: "周")]
        }

        let width = computeTotalWidth(units: units, style: style, monospaced: preferences.monospacedDigits)
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

    private static let captionFont: NSFont = .monospacedDigitSystemFont(ofSize: 6.6, weight: .medium)

    private static func unitWidth(_ unit: MetricUnit, style: SegmentDisplayStyle, monospaced: Bool) -> CGFloat {
        let pFont = primaryFont(monospaced: monospaced)
        let pW = ceil((unit.primaryText as NSString).size(withAttributes: [.font: pFont]).width)
        let cW = ceil((unit.captionText as NSString).size(withAttributes: [.font: captionFont]).width)
        let textW = max(27, max(pW, cW) + 2)

        switch style {
        case .rings:
            return ringSize + 2.5 + textW
        case .horizontalBar, .dualBars:
            return barWidth + 3.0 + textW
        case .compactBar, .statsMini:
            return textW
        case .progressOnly:
            return ringSize
        }
    }

    private static func computeTotalWidth(units: [MetricUnit], style: SegmentDisplayStyle, monospaced: Bool) -> CGFloat {
        let hPad: CGFloat = 9
        let iconAndGap: CGFloat = iconSize + 4.5
        let unitsSum = units.map { unitWidth($0, style: style, monospaced: monospaced) }.reduce(0, +)
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
            NSColor.labelColor.withAlphaComponent(isSelected ? 0.16 : 0.08).setFill()
            highlight.fill()
        }

        let midY = rect.midY
        var x = rect.minX + 4.5

        // Official SVG icon beside the segment
        let iconImg = BrandIconRenderer.statusIcon(
            for: provider,
            size: iconSize,
            mode: preferences.iconColorMode
        )
        iconImg.draw(in: NSRect(x: x, y: midY - iconSize / 2, width: iconSize, height: iconSize))
        x += iconSize + 4.5

        let pFont = primaryFont(monospaced: preferences.monospacedDigits)
        let primaryTextColor: NSColor = layout.isStale
            ? NSColor.labelColor.withAlphaComponent(0.62)
            : .labelColor
        let captionTextColor: NSColor = .secondaryLabelColor

        for (idx, unit) in layout.units.enumerated() {
            let uWidth = unitWidth(unit, style: layout.style, monospaced: preferences.monospacedDigits)
            let quotaColor = attentionNSColor(unit.attention)

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
                drawText(
                    unit.primaryText,
                    in: NSRect(x: x, y: 6.5, width: uWidth, height: 13),
                    font: pFont,
                    color: primaryTextColor,
                    alignment: .center
                )
                drawPillBar(
                    in: NSRect(x: x + 1, y: 2.0, width: max(12, uWidth - 2), height: barHeightVal),
                    percent: unit.quotaPercent,
                    color: quotaColor
                )

            case .statsMini:
                // CodexMeter unified baseline: bold value on top, compact caption below
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

        if layout.isStale {
            drawText(
                "!",
                in: NSRect(x: rect.maxX - 6, y: midY - 5, width: 6, height: 11),
                font: .systemFont(ofSize: 9, weight: .bold),
                color: .systemOrange,
                alignment: .center
            )
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
        let outerWidth: CGFloat = 2.8
        let innerWidth: CGFloat = 1.9
        let outerRadius = max(1, min(rect.width, rect.height) / 2 - outerWidth / 2)
        let innerRadius = max(1, outerRadius - outerWidth / 2 - 0.35 - innerWidth / 2)

        drawArc(
            center: center,
            radius: outerRadius,
            lineWidth: outerWidth,
            percent: nil,
            color: NSColor.labelColor.withAlphaComponent(0.22)
        )
        guard let quotaPercent else {
            drawText(
                "?",
                in: NSRect(x: rect.minX, y: rect.midY - 5, width: rect.width, height: 10),
                font: .systemFont(ofSize: 8, weight: .semibold),
                color: .secondaryLabelColor,
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
            color: CodexPalette.timeBlueNS.withAlphaComponent(0.22)
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
        NSColor.labelColor.withAlphaComponent(0.22).setFill()
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

    private static func attentionNSColor(_ level: QuotaAttentionLevel) -> NSColor {
        switch level {
        case .normal: return .labelColor
        case .warning: return CodexPalette.warningYellowNS
        case .critical: return CodexPalette.criticalRedNS
        }
    }

    static func renderCompositePreviewImage(
        preferences: UsageCenterPreferences,
        snapshots: [ProviderID: ProviderSnapshot]
    ) -> NSImage {
        let enabled = preferences.enabledSections
        guard !enabled.isEmpty else {
            return NSImage(size: NSSize(width: 100, height: barHeight), flipped: false) { rect in
                drawText("未启用分段", in: rect.insetBy(dx: 6, dy: 4), font: .systemFont(ofSize: 11), color: .secondaryLabelColor, alignment: .center)
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
                        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
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

// MARK: - Interactive Segment Subviews

final class ProviderSegmentItemView: NSView {
    let provider: ProviderID
    var layout: StatusSegmentRenderer.SegmentLayout
    var preferences: UsageCenterPreferences
    var isSelectedSegment: Bool = false {
        didSet { if oldValue != isSelectedSegment { needsDisplay = true } }
    }
    var onLeftClick: ((ProviderID, NSView) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    private var isHovered = false
    private var trackingRef: NSTrackingArea?

    init(provider: ProviderID, layout: StatusSegmentRenderer.SegmentLayout, preferences: UsageCenterPreferences) {
        self.provider = provider
        self.layout = layout
        self.preferences = preferences
        super.init(frame: NSRect(origin: .zero, size: layout.size))
        self.toolTip = "\(provider.displayName) — 点击查看详情"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingRef {
            removeTrackingArea(trackingRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick?(event)
            return
        }
        onLeftClick?(provider, self)
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    override func draw(_ dirtyRect: NSRect) {
        StatusSegmentRenderer.drawSegment(
            in: bounds,
            provider: provider,
            layout: layout,
            preferences: preferences,
            isHovered: isHovered,
            isSelected: isSelectedSegment
        )
    }
}

final class CompositeStatusBarView: NSView {
    var onSelectSegment: ((ProviderID, NSView) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    private var segmentViews: [ProviderID: ProviderSegmentItemView] = [:]
    private var dividerXs: [CGFloat] = []
    private var showsDividers = true

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func update(
        preferences: UsageCenterPreferences,
        snapshots: [ProviderID: ProviderSnapshot],
        selectedProvider: ProviderID?
    ) -> CGFloat {
        self.showsDividers = preferences.showsDividers
        let enabled = preferences.enabledSections
        let now = Date()

        let activeIDs = Set(enabled.map(\.provider))
        for (id, view) in segmentViews where !activeIDs.contains(id) {
            view.removeFromSuperview()
            segmentViews.removeValue(forKey: id)
        }

        guard !enabled.isEmpty else {
            dividerXs = []
            let fallback: CGFloat = 28
            setFrameSize(NSSize(width: fallback, height: StatusSegmentRenderer.barHeight))
            needsDisplay = true
            return fallback
        }

        let gapWidth: CGFloat = preferences.showsDividers ? 9 : 4
        var cursorX: CGFloat = 2
        var newDividers: [CGFloat] = []

        for (idx, cfg) in enabled.enumerated() {
            let snap = snapshots[cfg.provider] ?? ProviderSnapshot(provider: cfg.provider)
            let segLayout = StatusSegmentRenderer.buildLayout(
                config: cfg,
                snapshot: snap,
                preferences: preferences,
                now: now
            )

            let segView: ProviderSegmentItemView
            if let existing = segmentViews[cfg.provider] {
                existing.layout = segLayout
                existing.preferences = preferences
                segView = existing
            } else {
                let created = ProviderSegmentItemView(
                    provider: cfg.provider,
                    layout: segLayout,
                    preferences: preferences
                )
                created.onLeftClick = { [weak self] provider, anchorView in
                    self?.onSelectSegment?(provider, anchorView)
                }
                created.onRightClick = { [weak self] event in
                    self?.onRightClick?(event)
                }
                addSubview(created)
                segmentViews[cfg.provider] = created
                segView = created
            }

            segView.isSelectedSegment = (selectedProvider == cfg.provider)
            segView.frame = NSRect(
                x: cursorX,
                y: 0,
                width: segLayout.size.width,
                height: StatusSegmentRenderer.barHeight
            )
            segView.needsDisplay = true

            cursorX += segLayout.size.width
            if idx < enabled.count - 1 {
                if preferences.showsDividers {
                    newDividers.append(floor(cursorX + gapWidth / 2) + 0.5)
                }
                cursorX += gapWidth
            }
        }
        cursorX += 2

        dividerXs = newDividers
        setFrameSize(NSSize(width: cursorX, height: StatusSegmentRenderer.barHeight))
        needsDisplay = true
        return cursorX
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick?(event)
            return
        }
        if let first = subviews.compactMap({ $0 as? ProviderSegmentItemView }).first {
            onSelectSegment?(first.provider, first)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if segmentViews.isEmpty {
            let r = NSRect(x: bounds.midX - 7.5, y: bounds.midY - 7.5, width: 15, height: 15)
            BrandIconRenderer.statusIcon(for: .antigravity, size: 15, mode: .monochrome).draw(in: r)
            return
        }

        guard showsDividers else { return }
        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        for x in dividerXs {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: 4.5))
            line.line(to: NSPoint(x: x, y: bounds.height - 4.5))
            line.lineWidth = 1
            line.stroke()
        }
    }
}

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let store: UsageCenterStore
    private let onOpenSettings: () -> Void
    private let onOpenHistory: (ProviderID) -> Void
    private let statusItem: NSStatusItem
    private let compositeView = CompositeStatusBarView(frame: NSRect(x: 0, y: 0, width: 120, height: StatusSegmentRenderer.barHeight))
    private var activePopover: NSPopover?
    private var openedProvider: ProviderID?
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
        compositeView.frame = NSRect(x: 0, y: 0, width: 120, height: StatusSegmentRenderer.barHeight)
        button.addSubview(compositeView)

        compositeView.onSelectSegment = { [weak self] provider, anchorView in
            self?.toggleSegmentPopover(for: provider, relativeTo: anchorView)
        }
        compositeView.onRightClick = { [weak self] event in
            self?.presentContextMenu(with: event)
        }

        rebuildBar()
    }

    private func bindStore() {
        store.$preferences
            .combineLatest(store.$snapshots)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.rebuildBar()
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
            selectedProvider: (activePopover?.isShown == true) ? openedProvider : nil
        )
        statusItem.length = width
        if let button = statusItem.button {
            let yOffset = floor((button.bounds.height - StatusSegmentRenderer.barHeight) / 2)
            compositeView.setFrameOrigin(NSPoint(x: 0, y: max(0, yOffset)))
        }
    }

    private func toggleSegmentPopover(for provider: ProviderID, relativeTo anchorView: NSView) {
        if let current = activePopover, current.isShown, openedProvider == provider {
            closeActivePopover()
            return
        }

        if let previous = activePopover {
            previous.delegate = nil
            previous.animates = false
            previous.close()
            activePopover = nil
        }

        openedProvider = provider
        store.activeProvider = provider
        store.setPopoverVisible(true)
        rebuildBar()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let detailView = ProviderDetailPopoverView(
            provider: provider,
            store: store,
            onOpenSettings: { [weak self] in
                self?.closeActivePopover()
                self?.onOpenSettings()
            },
            onOpenHistory: { [weak self] targetProvider in
                self?.closeActivePopover()
                self?.onOpenHistory(targetProvider)
            }
        )
        popover.contentViewController = NSHostingController(rootView: detailView)
        activePopover = popover

        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closeActivePopover() {
        if let current = activePopover {
            current.delegate = nil
            current.animates = false
            current.close()
            activePopover = nil
        }
        openedProvider = nil
        store.setPopoverVisible(false)
        rebuildBar()
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover, closed === activePopover else {
            return
        }
        activePopover = nil
        openedProvider = nil
        store.setPopoverVisible(false)
        rebuildBar()
    }

    private func presentContextMenu(with event: NSEvent) {
        let menu = NSMenu()
        let refreshItem = NSMenuItem(title: "立即刷新全部", action: #selector(triggerRefreshAll), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let historyItem = NSMenuItem(title: "用量历史…", action: #selector(triggerOpenHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(triggerOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 UsageCenter", action: #selector(triggerQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        if let button = statusItem.button {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        }
    }

    @objc private func triggerRefreshAll() {
        Task { await store.refreshAll() }
    }

    @objc private func triggerOpenHistory() {
        closeActivePopover()
        onOpenHistory(store.activeProvider)
    }

    @objc private func triggerOpenSettings() {
        closeActivePopover()
        onOpenSettings()
    }

    @objc private func triggerQuit() {
        NSApplication.shared.terminate(nil)
    }
}
