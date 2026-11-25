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

                if activeProvider != .deepseek, snapshot.windows.count > 1 {
                    Picker("窗口", selection: Binding(
                        get: { store.historyWindowID ?? store.defaultHistoryWindowID(for: activeProvider) },
                        set: { store.historyWindowID = $0; store.hoveredQuotaPointID = nil }
                    )) {
                        ForEach(snapshot.windows) { win in
                            let label = win.groupName.map { "\($0) · \(win.title)" } ?? win.title
                            Text(label).tag(Optional(win.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
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

                HStack(spacing: 18) {
                    Label("实际配额", systemImage: "waveform.path")
                        .foregroundStyle(CodexPalette.chartAccentBright)
                    if !series.idealSegments.isEmpty {
                        Label("理想匀速线", systemImage: "line.diagonal")
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    if !series.gaps.isEmpty {
                        Label("未记录区间", systemImage: "rectangle.inset.filled")
                            .foregroundStyle(.white.opacity(0.55))
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

                if store.historyMode == .currentCycle, let reset = activeWindow?.resetsAt {
                    metricBlock(
                        title: "距离重置",
                        value: TimeFormatting.compactCountdown(until: reset, from: Date()),
                        tint: .white
                    )
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

        return Chart {
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
                    series: .value("周期面", pt.cycleID)
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

            if let hoveredPoint {
                RuleMark(x: .value("悬停", hoveredPoint.date))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                PointMark(
                    x: .value("时间", hoveredPoint.date),
                    y: .value("数值", hoveredPoint.value)
                )
                .foregroundStyle(.white)
                .symbolSize(52)
            } else if let latest = series.points.last {
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
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let plotOrigin = geo[proxy.plotFrame!].origin
                            let relX = location.x - plotOrigin.x
                            if let hoveredDate: Date = proxy.value(atX: relX) {
                                let nearest = series.points.min {
                                    abs($0.date.timeIntervalSince(hoveredDate)) < abs($1.date.timeIntervalSince(hoveredDate))
                                }
                                store.hoveredQuotaPointID = nearest?.id
                            }
                        case .ended:
                            store.hoveredQuotaPointID = nil
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
                Chart(bars) { bar in
                    let isHovered = (bar.bucketDate == store.hoveredTokenDate)
                    BarMark(
                        x: .value("时间", bar.bucketDate),
                        y: .value("Tokens", bar.tokens)
                    )
                    .foregroundStyle(isHovered ? Color.white : CodexPalette.chartAccentBright)
                    .cornerRadius(3)

                    if isHovered {
                        RuleMark(x: .value("选中", bar.bucketDate))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
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
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let loc):
                                    let origin = geo[proxy.plotFrame!].origin
                                    if let d: Date = proxy.value(atX: loc.x - origin.x) {
                                        let nearest = bars.min {
                                            abs($0.bucketDate.timeIntervalSince(d)) < abs($1.bucketDate.timeIntervalSince(d))
                                        }
                                        store.hoveredTokenDate = nearest?.bucketDate
                                    }
                                case .ended:
                                    store.hoveredTokenDate = nil
                                }
                            }
                    }
                }
                .frame(height: 220)
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
                    withAnimation(.easeInOut(duration: 0.16)) {
                        onSelect(opt)
                    }
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
