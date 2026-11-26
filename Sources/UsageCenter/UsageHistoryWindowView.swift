import AppKit
import Charts
import SwiftUI
import UsageCenterCore

/// Detailed CodexMeter-aligned Liquid Glass Usage History Window.
struct UsageHistoryWindowView: View {
    @ObservedObject var store: UsageCenterStore

    private var activeProvider: ProviderID {
        store.historyProvider
    }

    private var snapshot: ProviderSnapshot {
        store.snapshot(for: activeProvider)
    }

    private var samples: [QuotaHistoryPoint] {
        store.windowSamples(for: activeProvider, windowID: store.historyWindowID)
    }

    private var activeWindow: QuotaWindow? {
        store.activeWindowObject(for: activeProvider, windowID: store.historyWindowID)
    }

    private var chartSeries: QuotaChartSeries? {
        let liveBal = snapshot.preferredBalance(currencyPreference: store.preferences.deepSeekCurrencyPreference)?.numericTotal
        return HistoryAnalytics.buildQuotaSeries(
            samples: samples,
            mode: store.historyMode,
            calendarUnit: store.historyCalendarUnit,
            calendarOffset: store.historyCalendarOffset,
            activeWindow: activeWindow,
            isBalance: activeProvider == .deepseek,
            liveBalance: liveBal
        )
    }

    var body: some View {
        ZStack {
            HistoryBackdrop()
            scrollBody
                .safeAreaBar(edge: .top, spacing: 0) {
                    topBar
                }
        }
        .frame(minWidth: 780, idealWidth: 940, minHeight: 660, idealHeight: 860)
        .applyDarkLiquidGlassTheme()
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("用量历史")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text("多周期配额轨迹 · 消耗速率预测 · Token 统计")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(ProviderID.allCases) { p in
                    let selected = (p == activeProvider)
                    Button {
                        store.historyProvider = p
                        store.historyWindowID = store.defaultHistoryWindowID(for: p)
                        store.hoveredQuotaPointID = nil
                    } label: {
                        HStack(spacing: 5) {
                            BrandBadgeView(provider: p, size: 13)
                            Text(p.displayName)
                                .font(.caption.weight(selected ? .semibold : .medium))
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .background {
                            if selected {
                                Capsule().fill(CodexPalette.chartAccent.opacity(0.28))
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected ? .white : .white.opacity(0.70))
                }
            }
            .padding(4)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var scrollBody: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    quotaCard

                    if let tokenActivity = store.effectiveTokenActivity() {
                        tokenCard(tokenActivity)
                    }

                    recentSamplesLogCard
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 26)
            }
        }
        .onScrollPhaseChange { _, phase in
            let scrolling = phase.isScrolling
            store.isHistoryScrolling = scrolling
            if scrolling {
                if store.hoveredQuotaPointID != nil {
                    store.hoveredQuotaPointID = nil
                }
                if store.hoveredTokenDate != nil {
                    store.hoveredTokenDate = nil
                }
            }
        }
    }

    // MARK: - 1. Detailed Quota & Cycle History Card

    private var quotaCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeProvider == .deepseek ? "API 余额历史" : "配额历史")
                        .font(.title3.weight(.bold))
                    Text(rangeSubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                }

                Spacer()

                if activeProvider == .antigravity, snapshot.windows.count > 1 {
                    let isThirdParty = !(activeWindow?.groupName?.lowercased().contains("gemini") ?? true)
                    let currentKind: WindowKind = (activeWindow?.kind == .fiveHour) ? .fiveHour : .weekly

                    HStack(spacing: 8) {
                        capsulePair(
                            items: [("Gemini", false), ("第三方", true)],
                            selected: isThirdParty
                        ) { pickThirdParty in
                            if let target = snapshot.windows.first(where: {
                                (!(($0.groupName ?? "").lowercased().contains("gemini")) == pickThirdParty) && $0.kind == currentKind
                            }) ?? snapshot.windows.first(where: {
                                !(($0.groupName ?? "").lowercased().contains("gemini")) == pickThirdParty
                            }) {
                                store.historyWindowID = target.id
                                store.hoveredQuotaPointID = nil
                            }
                        }

                        capsulePair(
                            items: [("5h", WindowKind.fiveHour), ("7d", WindowKind.weekly)],
                            selected: currentKind
                        ) { pickKind in
                            if let target = snapshot.windows.first(where: {
                                (!(($0.groupName ?? "").lowercased().contains("gemini")) == isThirdParty) && $0.kind == pickKind
                            }) ?? snapshot.windows.first(where: { $0.kind == pickKind }) {
                                store.historyWindowID = target.id
                                store.hoveredQuotaPointID = nil
                            }
                        }
                    }
                } else if activeProvider != .deepseek, snapshot.windows.count > 1 {
                    capsulePair(
                        items: snapshot.windows.map { (shortHistoryWindowLabel($0), $0.id) },
                        selected: store.historyWindowID ?? store.defaultHistoryWindowID(for: activeProvider) ?? ""
                    ) { pickedID in
                        store.historyWindowID = pickedID
                        store.hoveredQuotaPointID = nil
                    }
                }
            }

            // 5 Range Modes (Current Cycle / 7d / 14d / 30d / Browse Calendar)
            capsuleOptionBar(
                options: HistoryQueryMode.allCases,
                selected: store.historyMode,
                title: \.localizedName
            ) { mode in
                store.historyMode = mode
                store.hoveredQuotaPointID = nil
            }

            if store.historyMode == .browse {
                calendarBrowserControls
            }

            if let series = chartSeries, !series.points.isEmpty {
                quotaHeadlineRow(series: series)

                interactiveQuotaChart(series: series)
                    .frame(height: 270)

                HStack(spacing: 20) {
                    ChartLegendItem(
                        kind: .actualCurve,
                        title: series.isBalanceSeries ? "余额曲线" : "实际配额"
                    )
                    if !series.idealSegments.isEmpty {
                        ChartLegendItem(
                            kind: .idealPace,
                            title: "理想匀速线"
                        )
                    }
                    if !series.gaps.isEmpty {
                        ChartLegendItem(
                            kind: .unrecordedGap,
                            title: "未记录区间"
                        )
                    }
                    Spacer()
                    if let proj = series.projectedExhaustionDate {
                        Text("按当前速率预计 \(TimeFormatting.fullDateTime(proj)) 耗尽")
                            .foregroundStyle(CodexPalette.warningYellow)
                    } else if let remProj = series.projectedRemainingAtReset {
                        Text("按当前速率预计重置时剩余 \(remProj)%")
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .font(.caption)
            } else {
                emptyChartPlaceholder(
                    title: "暂无该区间采样记录",
                    hint: "可在「设置 → 开发者」中一键生成多周期演示曲线查看完整效果。"
                )
            }
        }
        .padding(22)
        .liquidGlassSurface(cornerRadius: 22)
    }

    private var calendarBrowserControls: some View {
        let interval = store.historyCalendarUnit.interval(offset: store.historyCalendarOffset)
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy/MM/dd"
        let rangeLabel = "\(f.string(from: interval.start)) – \(f.string(from: interval.end.addingTimeInterval(-1)))"

        return HStack(spacing: 12) {
            capsuleOptionBar(
                options: HistoryCalendarUnit.allCases,
                selected: store.historyCalendarUnit,
                title: \.localizedName
            ) { unit in
                store.historyCalendarUnit = unit
                store.historyCalendarOffset = 0
            }

            HStack(spacing: 8) {
                Button {
                    store.historyCalendarOffset -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                Text(rangeLabel)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .frame(minWidth: 165)

                Button {
                    store.historyCalendarOffset = min(0, store.historyCalendarOffset + 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(store.historyCalendarOffset >= 0)

                if store.historyCalendarOffset != 0 {
                    Button("回到当前") {
                        store.historyCalendarOffset = 0
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CodexPalette.chartAccentBright)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08), in: Capsule())

            Spacer()
        }
    }

    private func quotaHeadlineRow(series: QuotaChartSeries) -> some View {
        let hoveredPoint = series.points.first { $0.id == store.hoveredQuotaPointID }
        let displayPoint = hoveredPoint ?? series.points.last

        return HStack(alignment: .lastTextBaseline, spacing: 26) {
            if series.isBalanceSeries {
                metricBlock(
                    title: hoveredPoint != nil ? "悬停时刻余额" : "当前余额",
                    value: String(format: "¥%.2f", displayPoint?.value ?? 0),
                    tint: CodexPalette.chartAccentBright
                )
            } else {
                metricBlock(
                    title: hoveredPoint != nil ? "悬停剩余配额" : "剩余配额",
                    value: "\(Int((displayPoint?.value ?? 0).rounded()))%",
                    tint: CodexPalette.chartAccentBright
                )

                let prefix = series.isLowerBoundConsumption ? "≥" : ""
                metricBlock(
                    title: "区间观测消耗",
                    value: "\(prefix)\(series.observedConsumedPercent)%",
                    tint: .white
                )

                if store.historyMode == .currentCycle {
                    if let reset = activeWindow?.resetsAt {
                        metricBlock(
                            title: "距离重置",
                            value: TimeFormatting.compactCountdown(until: reset, from: Date()),
                            tint: .white
                        )
                    } else if activeWindow?.remainingPercent == 100 {
                        metricBlock(
                            title: "距离重置",
                            value: "未开始",
                            tint: .white.opacity(0.85)
                        )
                    }
                }
            }

            if let hoveredPoint {
                metricBlock(
                    title: "采样时间",
                    value: TimeFormatting.fullDateTime(hoveredPoint.date),
                    tint: .white.opacity(0.85)
                )
            }

            Spacer()
        }
    }

    private func interactiveQuotaChart(series: QuotaChartSeries) -> some View {
        let hoveredPoint = series.points.first { $0.id == store.hoveredQuotaPointID }

        return StaticQuotaPlotView(series: series)
            .equatable()
            .chartOverlay { proxy in
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    guard !store.isHistoryScrolling,
                                          let plotAnchor = proxy.plotFrame else { return }
                                    let plotRect = geo[plotAnchor]
                                    guard plotRect.contains(location) else {
                                        if store.hoveredQuotaPointID != nil {
                                            store.hoveredQuotaPointID = nil
                                        }
                                        return
                                    }
                                    let relX = location.x - plotRect.minX
                                    if let hoveredDate: Date = proxy.value(atX: relX) {
                                        let nearestID = series.points.min {
                                            abs($0.date.timeIntervalSince(hoveredDate)) < abs($1.date.timeIntervalSince(hoveredDate))
                                        }?.id
                                        if store.hoveredQuotaPointID != nearestID {
                                            store.hoveredQuotaPointID = nearestID
                                        }
                                    }
                                case .ended:
                                    if store.hoveredQuotaPointID != nil {
                                        store.hoveredQuotaPointID = nil
                                    }
                                }
                            }

                        if let hoveredPoint,
                           let plotAnchor = proxy.plotFrame,
                           let px = proxy.position(forX: hoveredPoint.date),
                           let py = proxy.position(forY: hoveredPoint.value) {
                            let plotRect = geo[plotAnchor]
                            let xPos = plotRect.minX + px
                            let yPos = plotRect.minY + py

                            Path { path in
                                path.move(to: CGPoint(x: xPos, y: plotRect.minY))
                                path.addLine(to: CGPoint(x: xPos, y: plotRect.maxY))
                            }
                            .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .allowsHitTesting(false)

                            Circle()
                                .fill(Color.white)
                                .frame(width: 8.5, height: 8.5)
                                .position(x: xPos, y: yPos)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
    }

    // MARK: - 2. Detailed Token Activity Card (7d / 30d / 90d / 1y Weekly / All Monthly)

    private func tokenCard(_ activity: TokenActivitySnapshot) -> some View {
        let bars = HistoryAnalytics.aggregateTokens(
            dailyBuckets: activity.dailyBuckets,
            range: store.tokenRange
        )
        let totalInRange = bars.reduce(0) { $0 + $1.tokens }
        let peakBar = bars.max { $0.tokens < $1.tokens }
        let latestBar = bars.last
        let hoveredBar = bars.first { $0.bucketDate == store.hoveredTokenDate }

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Token 活动 (ChatGPT / Codex)")
                        .font(.title3.weight(.bold))
                    Text(store.tokenRange == .year1 ? "按周聚合统计" : (store.tokenRange == .all ? "按月聚合统计" : "每日消耗统计"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                }
                Spacer()
                if let streak = activity.currentStreakDays, streak > 0 {
                    Text("连续活跃 \(streak) 天")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CodexPalette.chartAccentBright)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(CodexPalette.chartAccent.opacity(0.18), in: Capsule())
                }
            }

            capsuleOptionBar(
                options: TokenHistoryRange.allCases,
                selected: store.tokenRange,
                title: \.localizedName
            ) { r in
                store.tokenRange = r
                store.hoveredTokenDate = nil
            }

            HStack(alignment: .lastTextBaseline, spacing: 26) {
                if let hoveredBar {
                    metricBlock(
                        title: "悬停周期 (\(hoveredBar.label))",
                        value: CompactTokenFormatter.format(hoveredBar.tokens),
                        tint: CodexPalette.chartAccentBright
                    )
                } else {
                    metricBlock(
                        title: "\(store.tokenRange.localizedName)总计",
                        value: CompactTokenFormatter.format(totalInRange),
                        tint: CodexPalette.chartAccentBright
                    )
                }

                if let latestBar {
                    metricBlock(
                        title: "最新周期",
                        value: CompactTokenFormatter.format(latestBar.tokens),
                        tint: .white
                    )
                }

                if let peakBar {
                    metricBlock(
                        title: "峰值 (\(peakBar.label))",
                        value: CompactTokenFormatter.format(peakBar.tokens),
                        tint: .white
                    )
                }

                if let lifetime = activity.lifetimeTokens {
                    metricBlock(
                        title: "历史累计",
                        value: CompactTokenFormatter.format(lifetime),
                        tint: .white.opacity(0.85)
                    )
                }

                Spacer()
            }

            if !bars.isEmpty {
                let calUnit = HistoryAnalytics.tokenCalendarComponent(for: store.tokenRange)
                let domain = HistoryAnalytics.tokenDomain(for: store.tokenRange, bars: bars)
                let barRatio: CGFloat = switch store.tokenRange {
                case .days7: 0.46
                case .days30: 0.72
                case .days90: 0.76
                case .year1: 0.72
                case .all: 0.54
                }

                StaticTokenBarsPlotView(
                    bars: bars,
                    calUnit: calUnit,
                    domain: domain,
                    barRatio: barRatio
                )
                .equatable()
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let loc):
                                        guard !store.isHistoryScrolling,
                                              let plotAnchor = proxy.plotFrame else { return }
                                        let plotRect = geo[plotAnchor]
                                        guard plotRect.contains(loc) else {
                                            if store.hoveredTokenDate != nil {
                                                store.hoveredTokenDate = nil
                                            }
                                            return
                                        }
                                        if let d: Date = proxy.value(atX: loc.x - plotRect.minX) {
                                            let nearestDate = bars.min {
                                                let m1 = bucketMidpoint(for: $0.bucketDate, unit: calUnit)
                                                let m2 = bucketMidpoint(for: $1.bucketDate, unit: calUnit)
                                                return abs(m1.timeIntervalSince(d)) < abs(m2.timeIntervalSince(d))
                                            }?.bucketDate
                                            if store.hoveredTokenDate != nearestDate {
                                                store.hoveredTokenDate = nearestDate
                                            }
                                        }
                                    case .ended:
                                        if store.hoveredTokenDate != nil {
                                            store.hoveredTokenDate = nil
                                        }
                                    }
                                }

                            if let hoveredBar,
                               let plotAnchor = proxy.plotFrame,
                               let px = proxy.position(forX: bucketMidpoint(for: hoveredBar.bucketDate, unit: calUnit)) {
                                let plotRect = geo[plotAnchor]
                                let xPos = plotRect.minX + px
                                Path { path in
                                    path.move(to: CGPoint(x: xPos, y: plotRect.minY))
                                    path.addLine(to: CGPoint(x: xPos, y: plotRect.maxY))
                                }
                                .stroke(Color.white.opacity(0.65), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                                .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .frame(height: 224)
            }
        }
        .padding(22)
        .liquidGlassSurface(cornerRadius: 22)
    }

    // MARK: - 3. Recent Sample Log & CSV Export Card

    private var recentSamplesLogCard: some View {
        let recent = Array(samples.suffix(8).reversed())

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("最近采样明细与导出")
                        .font(.headline)
                    Text("存储占用 \(ByteCountFormatter.string(fromByteCount: store.historyStorageBytes, countStyle: .file)) · 共 \(store.historySamples.count) 条记录")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                }
                Spacer()
                Button("导出 CSV") {
                    store.exportHistoryCSVInteractive()
                }
                .buttonStyle(.glass)
            }

            if !recent.isEmpty {
                VStack(spacing: 6) {
                    ForEach(recent) { item in
                        HStack {
                            Text(TimeFormatting.fullDateTime(item.timestamp))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.75))
                            Text(item.windowTitle)
                                .font(.caption)
                                .foregroundStyle(.white)
                            Spacer()
                            if let bal = item.balanceAmount {
                                Text(String(format: "¥%.2f", bal))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(CodexPalette.chartAccentBright)
                            } else {
                                Text("剩余 \(item.remainingPercent)%")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(CodexPalette.chartAccentBright)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(20)
        .liquidGlassSurface(cornerRadius: 22)
    }

    // MARK: - Shared Helpers

    private func bucketMidpoint(for date: Date, unit: Calendar.Component) -> Date {
        guard let iv = Calendar.current.dateInterval(of: unit, for: date) else { return date }
        return iv.start.addingTimeInterval(iv.duration / 2)
    }

    private func shortHistoryWindowLabel(_ win: QuotaWindow) -> String {
        switch win.kind {
        case .fiveHour:
            return "5h"
        case .weekly:
            return "7d"
        case .other:
            if let open = win.title.firstIndex(of: "("),
               let close = win.title.lastIndex(of: ")"),
               open < close {
                return String(win.title[win.title.index(after: open)..<close])
            }
            if let grp = win.groupName, !grp.isEmpty {
                let short = grp
                    .replacingOccurrences(of: "GPT-5.3-Codex-", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: " models", with: "", options: .caseInsensitive)
                return win.durationMinutes == 300 ? "\(short) 5h" : "\(short) 7d"
            }
            return win.title
        }
    }

    private func capsulePair<Value: Equatable>(
        items: [(String, Value)],
        selected: Value,
        onSelect: @escaping (Value) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let isSel = (item.1 == selected)
                Button {
                    onSelect(item.1)
                } label: {
                    Text(item.0)
                        .font(.caption.weight(isSel ? .semibold : .regular))
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background {
                            if isSel {
                                Capsule().fill(CodexPalette.chartAccent.opacity(0.32))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSel ? .white : .white.opacity(0.68))
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.08), in: Capsule())
        .animation(.easeOut(duration: 0.14), value: selected)
    }

    private var rangeSubtitle: String {
        switch store.historyMode {
        case .currentCycle: return "当前重置周期实测与理想匀速对比"
        case .days7: return "滚动近 7 天"
        case .days14: return "滚动近 14 天"
        case .days30: return "滚动近 30 天"
        case .browse: return "按日历周期浏览"
        }
    }

    private func capsuleOptionBar<T: Identifiable & Equatable>(
        options: [T],
        selected: T,
        title: @escaping (T) -> String,
        onSelect: @escaping (T) -> Void
    ) -> some View {
        HStack(spacing: 5) {
            ForEach(options) { opt in
                let isSel = (opt == selected)
                Button {
                    onSelect(opt)
                } label: {
                    Text(title(opt))
                        .font(.caption.weight(isSel ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .frame(height: 27)
                        .background {
                            if isSel {
                                Capsule().fill(CodexPalette.chartAccent.opacity(0.26))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSel ? .white : .white.opacity(0.68))
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.08), in: Capsule())
        .animation(.easeOut(duration: 0.14), value: selected)
    }

    private func metricBlock(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
        }
    }

    private func emptyChartPlaceholder(title: String, hint: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(CodexPalette.chartAccentBright)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(hint)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
    }
}

// MARK: - Equatable Static Swift Charts Subviews (Zero Re-Tessellation During Hover & Scroll)

private struct StaticQuotaPlotView: View, Equatable {
    let series: QuotaChartSeries

    var body: some View {
        Chart {
            ForEach(series.gaps) { gap in
                RectangleMark(
                    xStart: .value("缺口起点", gap.start),
                    xEnd: .value("缺口终点", gap.end),
                    yStart: .value("下界", 0),
                    yEnd: .value("上界", series.isBalanceSeries ? (series.points.map(\.value).max() ?? 100) : 100)
                )
                .foregroundStyle(Color.white.opacity(0.07))
            }

            ForEach(series.idealSegments) { seg in
                LineMark(
                    x: .value("时间", seg.start),
                    y: .value("理想线", seg.startValue),
                    series: .value("理想", seg.id)
                )
                .foregroundStyle(Color.white.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 5]))

                LineMark(
                    x: .value("时间", seg.end),
                    y: .value("理想线", seg.endValue),
                    series: .value("理想", seg.id)
                )
                .foregroundStyle(Color.white.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 5]))
            }

            ForEach(series.points) { pt in
                AreaMark(
                    x: .value("时间", pt.date),
                    y: .value("数值", pt.value),
                    series: .value("周期面", pt.cycleID),
                    stacking: .unstacked
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [CodexPalette.chartAccent.opacity(0.30), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("时间", pt.date),
                    y: .value("数值", pt.value),
                    series: .value("周期线", pt.cycleID)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(CodexPalette.chartAccentBright)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }

            if let latest = series.points.last {
                PointMark(
                    x: .value("时间", latest.date),
                    y: .value("数值", latest.value)
                )
                .foregroundStyle(CodexPalette.chartAccentBright)
                .symbolSize(40)
            }
        }
        .chartXScale(domain: series.domain)
        .chartYScale(domain: series.isBalanceSeries
            ? 0...(max(10, (series.points.map(\.value).max() ?? 50) * 1.15))
            : 0...100
        )
        .clipped()
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct StaticTokenBarsPlotView: View, Equatable {
    let bars: [AggregatedTokenBar]
    let calUnit: Calendar.Component
    let domain: ClosedRange<Date>
    let barRatio: CGFloat

    var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("时间", bar.bucketDate, unit: calUnit),
                y: .value("Tokens", bar.tokens),
                width: .ratio(barRatio)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [CodexPalette.chartAccentBright, CodexPalette.chartAccent.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(4)
        }
        .chartXScale(domain: domain)
        .clipped()
        .transaction { transaction in
            transaction.animation = nil
        }
        .chartYAxis {
            AxisMarks(position: .leading) { val in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.12))
                AxisValueLabel {
                    if let num = val.as(Int64.self) {
                        Text(CompactTokenFormatter.format(num))
                            .foregroundStyle(.white.opacity(0.70))
                    }
                }
            }
        }
    }
}
