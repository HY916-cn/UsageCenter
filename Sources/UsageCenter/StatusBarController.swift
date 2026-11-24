import AppKit
import Combine
import SwiftUI
import UsageCenterCore

enum StatusSegmentRenderer {
    static let barHeight: CGFloat = 22

    struct SegmentMetrics {
        let size: NSSize
        let topLine: String
        let bottomLine: String?
        let singleLine: String
        let primaryProgress: Double?
        let secondaryProgress: Double?
        let attention: QuotaAttentionLevel
        let isStale: Bool
    }

    static func computeMetrics(
        config: ProviderSectionConfig,
        snapshot: ProviderSnapshot,
        preferences: UsageCenterPreferences,
        now: Date = Date()
    ) -> SegmentMetrics {
        let style = preferences.effectiveStyle(for: config.provider)
        let prefix = config.showsProviderLabel ? "\(config.provider.shortLabel) " : ""

        if config.provider == .deepseek {
            let balanceText: String
            let progress: Double?
            let attention: QuotaAttentionLevel
            if let item = snapshot.preferredBalance(currencyPreference: preferences.deepSeekCurrencyPreference) {
                balanceText = item.formattedTotal
                let amount = item.numericTotal
                progress = min(1.0, max(0.05, amount / 100.0))
                attention = (snapshot.isAvailable == false || amount <= 1.0) ? .critical : (amount < 10.0 ? .warning : .normal)
            } else if snapshot.isLoading {
                balanceText = "…"
                progress = nil
                attention = .normal
            } else {
                balanceText = "未配置"
                progress = nil
                attention = .warning
            }

            let top = prefix + (style == .stack ? "余额" : balanceText)
            let bottom: String? = (style == .stack) ? balanceText : nil
            let single = prefix + balanceText
            let width = measureSegmentWidth(
                style: style,
                topLine: top,
                bottomLine: bottom,
                singleLine: single,
                monospaced: preferences.monospacedDigits,
                isDeepSeek: true
            )
            return SegmentMetrics(
                size: NSSize(width: width, height: barHeight),
                topLine: top,
                bottomLine: bottom,
                singleLine: single,
                primaryProgress: progress,
                secondaryProgress: nil,
                attention: attention,
                isStale: snapshot.isStale
            )
        }

        let pair = snapshot.resolvedWindows(antigravityGroup: preferences.antigravityGroup)
        let fiveHour = pair.fiveHour
        let weekly = pair.weekly
        let tightest = snapshot.mostConstrainedWindow(antigravityGroup: preferences.antigravityGroup)
        let timeMode: TimeDisplayMode = config.showsResetTimeInMenuBar ? preferences.timeDisplayMode : .hidden

        func formatWindow(_ window: QuotaWindow?, tag: String) -> String {
            guard let window else {
                return snapshot.isLoading ? "\(tag) …" : "\(tag) --"
            }
            let pct = window.displayPercent(mode: preferences.percentMode)
            if let timeStr = window.shortTimeLabel(at: now, mode: timeMode) {
                return "\(tag) \(pct)%·\(timeStr)"
            }
            return "\(tag) \(pct)%"
        }

        let topLine: String
        let bottomLine: String?
        let singleLine: String

        switch config.windowVisibility {
        case .both:
            topLine = prefix + formatWindow(fiveHour, tag: "5h")
            bottomLine = formatWindow(weekly, tag: "7d")
            let p5 = fiveHour.map { "\($0.displayPercent(mode: preferences.percentMode))%" } ?? (snapshot.isLoading ? "…" : "--")
            let p7 = weekly.map { "\($0.displayPercent(mode: preferences.percentMode))%" } ?? (snapshot.isLoading ? "…" : "--")
            if let t5 = fiveHour?.shortTimeLabel(at: now, mode: timeMode),
               let t7 = weekly?.shortTimeLabel(at: now, mode: timeMode) {
                singleLine = "\(prefix)\(p5)(\(t5)) / \(p7)(\(t7))"
            } else {
                singleLine = "\(prefix)\(p5) / \(p7)"
            }
        case .fiveHourOnly:
            let text = formatWindow(fiveHour, tag: "5h")
            topLine = prefix + text
            bottomLine = nil
            singleLine = prefix + text
        case .weeklyOnly:
            let text = formatWindow(weekly, tag: "7d")
            topLine = prefix + text
            bottomLine = nil
            singleLine = prefix + text
        case .mostConstrained:
            let tag = (tightest?.kind == .weekly) ? "7d" : "5h"
            let text = formatWindow(tightest, tag: tag)
            topLine = prefix + text
            bottomLine = nil
            singleLine = prefix + text
        }

        let p1 = (fiveHour ?? tightest).map { Double($0.displayPercent(mode: preferences.percentMode)) / 100.0 }
        let p2 = weekly.map { Double($0.displayPercent(mode: preferences.percentMode)) / 100.0 }
        let attention = tightest?.attentionLevel(at: now) ?? .normal

        let width = measureSegmentWidth(
            style: style,
            topLine: topLine,
            bottomLine: bottomLine,
            singleLine: singleLine,
            monospaced: preferences.monospacedDigits,
            isDeepSeek: false
        )

        return SegmentMetrics(
            size: NSSize(width: width, height: barHeight),
            topLine: topLine,
            bottomLine: bottomLine,
            singleLine: singleLine,
            primaryProgress: p1,
            secondaryProgress: p2,
            attention: attention,
            isStale: snapshot.isStale
        )
    }

    private static func measureSegmentWidth(
        style: SegmentDisplayStyle,
        topLine: String,
        bottomLine: String?,
        singleLine: String,
        monospaced: Bool,
        isDeepSeek: Bool
    ) -> CGFloat {
        let iconSpace: CGFloat = 15 + 5 // icon + gap
        let hPad: CGFloat = 10

        let stackFont: NSFont = monospaced
            ? .monospacedDigitSystemFont(ofSize: 9.0, weight: .medium)
            : .systemFont(ofSize: 9.0, weight: .medium)
        let singleFont: NSFont = monospaced
            ? .monospacedDigitSystemFont(ofSize: 11.0, weight: .medium)
            : .systemFont(ofSize: 11.0, weight: .medium)

        func textWidth(_ s: String, font: NSFont) -> CGFloat {
            ceil((s as NSString).size(withAttributes: [.font: font]).width)
        }

        switch style {
        case .stack:
            if let bottomLine {
                let w = max(textWidth(topLine, font: stackFont), textWidth(bottomLine, font: stackFont))
                return hPad + iconSpace + w + 2
            } else {
                return hPad + iconSpace + textWidth(singleLine, font: singleFont) + 2
            }
        case .rings:
            let ringWidth: CGFloat = 15 + 4
            if bottomLine != nil && !isDeepSeek {
                let w = max(textWidth(topLine, font: stackFont), textWidth(bottomLine ?? "", font: stackFont))
                return hPad + iconSpace + ringWidth + w + 2
            } else {
                return hPad + iconSpace + ringWidth + textWidth(singleLine, font: singleFont) + 2
            }
        case .bars:
            let barWidth: CGFloat = 22 + 5
            if bottomLine != nil && !isDeepSeek {
                let w = max(textWidth(topLine, font: stackFont), textWidth(bottomLine ?? "", font: stackFont))
                return hPad + iconSpace + barWidth + w + 2
            } else {
                return hPad + iconSpace + barWidth + textWidth(singleLine, font: singleFont) + 2
            }
        case .compact:
            return hPad + iconSpace + textWidth(singleLine, font: singleFont) + 2
        case .minimal:
            return isDeepSeek ? (hPad + iconSpace + textWidth(singleLine, font: singleFont)) : (hPad + iconSpace + 16)
        }
    }

    static func drawSegment(
        in rect: NSRect,
        config: ProviderSectionConfig,
        snapshot: ProviderSnapshot,
        preferences: UsageCenterPreferences,
        metrics: SegmentMetrics,
        isHovered: Bool,
        isSelected: Bool
    ) {
        if isHovered || isSelected {
            let pill = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1.5), xRadius: 5, yRadius: 5)
            NSColor.labelColor.withAlphaComponent(isSelected ? 0.16 : 0.09).setFill()
            pill.fill()
        }

        let style = preferences.effectiveStyle(for: config.provider)
        var x: CGFloat = rect.minX + 5
        let midY = rect.midY

        // 1. Brand Icon beside segment
        let iconSize: CGFloat = 14.5
        let iconRect = NSRect(x: x, y: midY - iconSize / 2, width: iconSize, height: iconSize)
        let tint: NSColor? = (preferences.iconColorMode == .monochrome) ? .labelColor : nil
        let iconImg = BrandIconRenderer.statusIcon(
            for: config.provider,
            size: iconSize,
            mode: preferences.iconColorMode,
            tintOverride: tint
        )
        iconImg.draw(in: iconRect)
        x += iconSize + 4.5

        let accentColor = statusColor(
            provider: config.provider,
            attention: metrics.attention,
            iconMode: preferences.iconColorMode
        )

        // 2. Optional Visual Indicator (Rings / Bars / Minimal)
        switch style {
        case .rings:
            drawConcentricRings(
                in: NSRect(x: x, y: midY - 7.2, width: 14.4, height: 14.4),
                outer: metrics.primaryProgress,
                inner: metrics.secondaryProgress,
                color: accentColor
            )
            x += 18.5
        case .bars:
            drawDualBars(
                in: NSRect(x: x, y: midY - 5.5, width: 22, height: 11),
                top: metrics.primaryProgress,
                bottom: metrics.secondaryProgress,
                color: accentColor
            )
            x += 26.5
        case .minimal:
            if config.provider != .deepseek {
                drawConcentricRings(
                    in: NSRect(x: x, y: midY - 7.2, width: 14.4, height: 14.4),
                    outer: metrics.primaryProgress,
                    inner: metrics.secondaryProgress,
                    color: accentColor
                )
                return
            }
        case .stack, .compact:
            break
        }

        // 3. Text Readout
        let textWidth = max(10, rect.maxX - x - 4)
        let stackFont: NSFont = preferences.monospacedDigits
            ? .monospacedDigitSystemFont(ofSize: 9.0, weight: .medium)
            : .systemFont(ofSize: 9.0, weight: .medium)
        let singleFont: NSFont = preferences.monospacedDigits
            ? .monospacedDigitSystemFont(ofSize: 11.0, weight: .medium)
            : .systemFont(ofSize: 11.0, weight: .medium)

        let textColor: NSColor = metrics.isStale
            ? NSColor.labelColor.withAlphaComponent(0.62)
            : NSColor.labelColor

        if (style == .stack || style == .rings || style == .bars),
           let bottomLine = metrics.bottomLine,
           !(config.provider == .deepseek && style != .stack) {
            drawLabel(
                metrics.topLine,
                in: NSRect(x: x, y: midY - 0.5, width: textWidth, height: 10.5),
                font: stackFont,
                color: config.provider == .deepseek ? .secondaryLabelColor : textColor
            )
            drawLabel(
                bottomLine,
                in: NSRect(x: x, y: midY - 10.5, width: textWidth, height: 10.5),
                font: stackFont,
                color: config.provider == .deepseek ? textColor : textColor.withAlphaComponent(0.88)
            )
        } else {
            drawLabel(
                metrics.singleLine,
                in: NSRect(x: x, y: midY - 7, width: textWidth, height: 14),
                font: singleFont,
                color: textColor
            )
        }
    }

    private static func statusColor(
        provider: ProviderID,
        attention: QuotaAttentionLevel,
        iconMode: IconColorMode
    ) -> NSColor {
        switch attention {
        case .critical:
            return .systemRed
        case .warning:
            return .systemOrange
        case .normal:
            return iconMode == .brand ? BrandIconRenderer.brandAccentColor(for: provider) : .labelColor
        }
    }

    private static func drawConcentricRings(
        in rect: NSRect,
        outer: Double?,
        inner: Double?,
        color: NSColor
    ) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let outerR = rect.width / 2 - 1.4
        let innerR = outerR - 3.0

        drawArc(center: center, radius: outerR, width: 2.1, progress: nil, color: NSColor.labelColor.withAlphaComponent(0.18))
        if let outer {
            drawArc(center: center, radius: outerR, width: 2.1, progress: outer, color: color)
        }
        if let inner {
            drawArc(center: center, radius: innerR, width: 1.7, progress: nil, color: NSColor.labelColor.withAlphaComponent(0.15))
            drawArc(center: center, radius: innerR, width: 1.7, progress: inner, color: color.withAlphaComponent(0.78))
        }
    }

    private static func drawArc(
        center: NSPoint,
        radius: CGFloat,
        width: CGFloat,
        progress: Double?,
        color: NSColor
    ) {
        guard radius > 0.5 else { return }
        let path = NSBezierPath()
        if let progress {
            let clamped = CGFloat(min(1.0, max(0.0, progress)))
            guard clamped > 0.01 else { return }
            path.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - 360 * clamped,
                clockwise: true
            )
            path.lineCapStyle = .round
        } else {
            path.appendOval(in: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    private static func drawDualBars(
        in rect: NSRect,
        top: Double?,
        bottom: Double?,
        color: NSColor
    ) {
        let h: CGFloat = 3.6
        let topRect = NSRect(x: rect.minX, y: rect.maxY - h - 0.5, width: rect.width, height: h)
        let botRect = NSRect(x: rect.minX, y: rect.minY + 0.5, width: rect.width, height: h)

        drawSingleBar(in: topRect, progress: top, color: color)
        if bottom != nil {
            drawSingleBar(in: botRect, progress: bottom, color: color.withAlphaComponent(0.75))
        } else {
            drawSingleBar(in: NSRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h), progress: top, color: color)
        }
    }

    private static func drawSingleBar(in rect: NSRect, progress: Double?, color: NSColor) {
        let track = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSColor.labelColor.withAlphaComponent(0.18).setFill()
        track.fill()

        guard let progress else { return }
        let clamped = CGFloat(min(1.0, max(0.0, progress)))
        guard clamped > 0.01 else { return }
        let fillRect = NSRect(
            x: rect.minX,
            y: rect.minY,
            width: max(rect.height, rect.width * clamped),
            height: rect.height
        )
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        color.setFill()
        fill.fill()
    }

    private static func drawLabel(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineBreakMode = .byClipping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    static func renderCompositePreviewImage(
        preferences: UsageCenterPreferences,
        snapshots: [ProviderID: ProviderSnapshot]
    ) -> NSImage {
        let enabled = preferences.enabledSections
        guard !enabled.isEmpty else {
            return NSImage(size: NSSize(width: 90, height: barHeight), flipped: false) { rect in
                drawLabel("未启用分段", in: rect.insetBy(dx: 8, dy: 4), font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
                return true
            }
        }

        let now = Date()
        let items: [(ProviderSectionConfig, ProviderSnapshot, SegmentMetrics)] = enabled.map { cfg in
            let snap = snapshots[cfg.provider] ?? ProviderSnapshot(provider: cfg.provider)
            let m = computeMetrics(config: cfg, snapshot: snap, preferences: preferences, now: now)
            return (cfg, snap, m)
        }

        let dividerSpace: CGFloat = preferences.showsDividers ? 7 : 2
        let totalWidth = items.map(\.2.size.width).reduce(0, +)
            + CGFloat(max(0, items.count - 1)) * dividerSpace + 4

        let img = NSImage(size: NSSize(width: totalWidth, height: barHeight), flipped: false) { _ in
            var x: CGFloat = 2
            for (index, entry) in items.enumerated() {
                let segRect = NSRect(x: x, y: 0, width: entry.2.size.width, height: barHeight)
                drawSegment(
                    in: segRect,
                    config: entry.0,
                    snapshot: entry.1,
                    preferences: preferences,
                    metrics: entry.2,
                    isHovered: false,
                    isSelected: false
                )
                x += entry.2.size.width
                if index < items.count - 1 {
                    if preferences.showsDividers {
                        let lineX = floor(x + dividerSpace / 2) + 0.5
                        let line = NSBezierPath()
                        line.move(to: NSPoint(x: lineX, y: 5))
                        line.line(to: NSPoint(x: lineX, y: barHeight - 5))
                        line.lineWidth = 1
                        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
                        line.stroke()
                    }
                    x += dividerSpace
                }
            }
            return true
        }
        img.isTemplate = false
        return img
    }
}

// MARK: - Interactive Status Bar View & Controller

final class CompositeStatusBarView: NSView {
    struct SegmentSlot {
        let provider: ProviderID
        let config: ProviderSectionConfig
        let snapshot: ProviderSnapshot
        let metrics: StatusSegmentRenderer.SegmentMetrics
        let frame: NSRect
    }

    var onSelectSegment: ((ProviderID, NSRect) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    private(set) var slots: [SegmentSlot] = []
    private var preferences = UsageCenterPreferences()
    private var hoveredProvider: ProviderID?
    private var selectedProvider: ProviderID?
    private var trackingAreaRef: NSTrackingArea?

    override var intrinsicContentSize: NSSize {
        frame.size
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

        if enabled.isEmpty {
            slots = []
            let fallbackWidth: CGFloat = 32
            setFrameSize(NSSize(width: fallbackWidth, height: StatusSegmentRenderer.barHeight))
            needsDisplay = true
            return fallbackWidth
        }

        let dividerSpace: CGFloat = preferences.showsDividers ? 7 : 2
        var cursorX: CGFloat = 2
        var builtSlots: [SegmentSlot] = []

        for (idx, cfg) in enabled.enumerated() {
            let snap = snapshots[cfg.provider] ?? ProviderSnapshot(provider: cfg.provider)
            let metrics = StatusSegmentRenderer.computeMetrics(
                config: cfg,
                snapshot: snap,
                preferences: preferences,
                now: now
            )
            let segRect = NSRect(x: cursorX, y: 0, width: metrics.size.width, height: StatusSegmentRenderer.barHeight)
            builtSlots.append(SegmentSlot(
                provider: cfg.provider,
                config: cfg,
                snapshot: snap,
                metrics: metrics,
                frame: segRect
            ))
            cursorX += metrics.size.width
            if idx < enabled.count - 1 {
                cursorX += dividerSpace
            }
        }
        cursorX += 2

        slots = builtSlots
        setFrameSize(NSSize(width: cursorX, height: StatusSegmentRenderer.barHeight))
        needsDisplay = true
        return cursorX
    }

    func rect(for provider: ProviderID) -> NSRect? {
        slots.first { $0.provider == provider }?.frame
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let hit = slots.first { $0.frame.contains(pt) }?.provider
        if hit != hoveredProvider {
            hoveredProvider = hit
            toolTip = hit.map { "\($0.displayName) — 点击查看详情" }
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredProvider != nil {
            hoveredProvider = nil
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick?(event)
            return
        }
        let pt = convert(event.locationInWindow, from: nil)
        if let slot = slots.first(where: { $0.frame.contains(pt) }) {
            onSelectSegment?(slot.provider, slot.frame)
        } else if let first = slots.first {
            onSelectSegment?(first.provider, first.frame)
        } else {
            onSelectSegment?(.claude, bounds)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !slots.isEmpty else {
            let iconRect = NSRect(x: bounds.midX - 8, y: bounds.midY - 8, width: 16, height: 16)
            BrandIconRenderer.statusIcon(for: .antigravity, size: 16, mode: preferences.iconColorMode).draw(in: iconRect)
            return
        }

        let dividerSpace: CGFloat = preferences.showsDividers ? 7 : 2
        for (idx, slot) in slots.enumerated() {
            StatusSegmentRenderer.drawSegment(
                in: slot.frame,
                config: slot.config,
                snapshot: slot.snapshot,
                preferences: preferences,
                metrics: slot.metrics,
                isHovered: hoveredProvider == slot.provider,
                isSelected: selectedProvider == slot.provider
            )
            if preferences.showsDividers, idx < slots.count - 1 {
                let lineX = floor(slot.frame.maxX + dividerSpace / 2) + 0.5
                let path = NSBezierPath()
                path.move(to: NSPoint(x: lineX, y: 5))
                path.line(to: NSPoint(x: lineX, y: bounds.height - 5))
                path.lineWidth = 1
                NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
                path.stroke()
            }
        }
    }
}

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let store: UsageCenterStore
    private let onOpenSettings: () -> Void
    private let statusItem: NSStatusItem
    private let compositeView = CompositeStatusBarView(frame: NSRect(x: 0, y: 0, width: 120, height: StatusSegmentRenderer.barHeight))
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var minuteTickTimer: Timer?
    private var openedSegmentProvider: ProviderID?

    init(store: UsageCenterStore, onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        setupPopover()
        setupStatusItem()
        bindStore()
        startCountdownRefreshTimer()
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let rootView = ProviderDetailPopoverView(
            store: store,
            onOpenSettings: { [weak self] in
                self?.closePopover()
                self?.onOpenSettings()
            },
            onClosePopover: { [weak self] in
                self?.closePopover()
            }
        )
        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    private func setupStatusItem() {
        statusItem.autosaveName = "UsageCenterUnifiedStatusItem"
        guard let button = statusItem.button else { return }
        button.image = NSImage()
        button.title = ""
        compositeView.frame = NSRect(x: 0, y: 0, width: 120, height: StatusSegmentRenderer.barHeight)
        button.addSubview(compositeView)

        compositeView.onSelectSegment = { [weak self] provider, segmentRect in
            self?.handleSegmentClick(provider: provider, segmentRect: segmentRect)
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

        store.$activeProvider
            .receive(on: RunLoop.main)
            .sink { [weak self] provider in
                guard let self, self.popover.isShown else { return }
                self.openedSegmentProvider = provider
                self.rebuildBar()
                if let rect = self.compositeView.rect(for: provider) {
                    self.popover.positioningRect = rect
                }
            }
            .store(in: &cancellables)
    }

    private func startCountdownRefreshTimer() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildBar()
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        minuteTickTimer = timer
    }

    private func rebuildBar() {
        let width = compositeView.update(
            preferences: store.preferences,
            snapshots: store.snapshots,
            selectedProvider: popover.isShown ? openedSegmentProvider : nil
        )
        statusItem.length = width
        if let button = statusItem.button {
            let yOffset = floor((button.bounds.height - StatusSegmentRenderer.barHeight) / 2)
            compositeView.setFrameOrigin(NSPoint(x: 0, y: max(0, yOffset)))
        }
    }

    private func handleSegmentClick(provider: ProviderID, segmentRect: NSRect) {
        if popover.isShown, openedSegmentProvider == provider {
            closePopover()
            return
        }

        openedSegmentProvider = provider
        store.activeProvider = provider
        rebuildBar()

        if popover.isShown {
            popover.performClose(nil)
        }
        popover.show(relativeTo: segmentRect, of: compositeView, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        openedSegmentProvider = nil
        popover.performClose(nil)
        rebuildBar()
    }

    func popoverDidClose(_ notification: Notification) {
        openedSegmentProvider = nil
        rebuildBar()
    }

    private func presentContextMenu(with event: NSEvent) {
        let menu = NSMenu()
        let refreshItem = NSMenuItem(title: "立即刷新全部用量", action: #selector(triggerRefreshAll), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let settingsItem = NSMenuItem(title: "打开设置…", action: #selector(triggerOpenSettings), keyEquivalent: ",")
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

    @objc private func triggerOpenSettings() {
        closePopover()
        onOpenSettings()
    }

    @objc private func triggerQuit() {
        NSApplication.shared.terminate(nil)
    }
}
