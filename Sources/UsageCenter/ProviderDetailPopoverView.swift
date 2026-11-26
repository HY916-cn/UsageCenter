import AppKit
import Charts
import SwiftUI
import UsageCenterCore

/// Unscrolled, auto-sizing Liquid Glass detail view dedicated to the clicked segment.
struct ProviderDetailPopoverView: View {
    @ObservedObject var store: UsageCenterStore
    let onOpenSettings: () -> Void
    let onOpenHistory: (ProviderID) -> Void

    private var provider: ProviderID {
        store.activeProvider
    }

    private var snapshot: ProviderSnapshot {
        store.snapshot(for: provider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection

            if snapshot.isStale {
                Label("缓存数据", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(CodexPalette.warningYellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CodexPalette.warningYellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }

            thinDivider

            mainContentSection

            thinDivider

            settingsButtonRow

            thinDivider

            footerRow
        }
        .padding(16)
        .frame(width: 384)
        .fixedSize(horizontal: false, vertical: true)
        .applyDarkLiquidGlassTheme()
        .id(provider)
        .onAppear {
            Task { await store.refresh(provider: provider) }
        }
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(height: 0.8)
    }

    // MARK: - Concise Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            BrandBadgeView(provider: provider, size: 19)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.headline)
                    .foregroundStyle(.white)

                if let label = snapshot.accountLabel {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
                }
            }

            Spacer()

            Button {
                Task { await store.refresh(provider: provider) }
            } label: {
                ZStack {
                    if store.isRefreshing(provider) {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing(provider))
        }
    }

    // MARK: - Unscrolled Content Stack

    @ViewBuilder
    private var mainContentSection: some View {
        if snapshot.isLoading && !snapshot.hasData {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("读取中…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, minHeight: 72)
        } else if let error = snapshot.errorMessage, !snapshot.hasData {
            VStack(alignment: .leading, spacing: 8) {
                Label("读取失败", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CodexPalette.warningYellow)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("重试") {
                        Task { await store.refresh(provider: provider) }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)

                    Button("设置") {
                        store.selectedSettingsCategory = .cliAndAccounts
                        onOpenSettings()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(activeSections.enumerated()), id: \.element.id) { idx, kind in
                    if idx > 0 {
                        thinDivider
                    }
                    switch kind {
                    case .quotaDetails:
                        if provider == .deepseek {
                            deepSeekWalletView
                        } else {
                            quotaWindowsView
                        }
                    case .quotaHistory:
                        inlineHistorySection
                    case .tokenActivity:
                        if let tokens = store.effectiveTokenActivity(), provider == .chatgpt {
                            Button {
                                onOpenHistory(.chatgpt)
                            } label: {
                                miniTokenPreview(tokens)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var activeSections: [PopoverSectionKind] {
        store.preferences.visiblePopoverSections.filter { section in
            switch section {
            case .quotaDetails:
                return snapshot.hasData
            case .quotaHistory:
                return true
            case .tokenActivity:
                return provider == .chatgpt && store.effectiveTokenActivity() != nil
            }
        }
    }

    // MARK: - Quota Windows

    private var quotaWindowsView: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(snapshot.windows.enumerated()), id: \.element.id) { idx, win in
                    if idx > 0 {
                        thinDivider
                    }
                    ConciseWindowRow(
                        window: win,
                        now: context.date,
                        percentMode: store.preferences.percentMode,
                        lowThreshold: store.preferences.lowQuotaThreshold
                    )
                }
            }
        }
    }

    // MARK: - DeepSeek DSH Wallet

    private var deepSeekWalletView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(snapshot.balances.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 {
                    thinDivider
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("可用余额 (\(item.currency))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        let ok = snapshot.isAvailable ?? (item.numericTotal > 0)
                        Label(ok ? "正常" : "不足", systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(ok ? Color.green : CodexPalette.warningYellow)
                    }

                    Text(item.formattedTotal)
                        .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)

                    LuminousBar(
                        label: nil,
                        valueText: nil,
                        percent: min(100, max(4, item.numericTotal)),
                        tint: item.numericTotal < 10 ? CodexPalette.warningYellow : CodexPalette.timeBlue
                    )

                    HStack(spacing: 12) {
                        compactStatPill(title: "充值", value: item.formattedToppedUp)
                        compactStatPill(title: "赠送", value: item.formattedGranted)
                        if let cost = item.formattedTotalCost {
                            compactStatPill(title: "累计消耗", value: cost)
                        }
                    }
                }
            }
        }
    }

    private func compactStatPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Expanded Inline Quota / Balance History

    private var inlineHistorySection: some View {
        let selectedWinID = store.selectedPopoverHistoryWindowID(for: provider)
        let samples = store.windowSamples(for: provider, windowID: selectedWinID)
        let activeWin = store.activeWindowObject(for: provider, windowID: selectedWinID)
        let liveBal = snapshot.preferredBalance(currencyPreference: store.preferences.deepSeekCurrencyPreference)?.numericTotal
        let series = HistoryAnalytics.buildQuotaSeries(
            samples: samples,
            mode: .currentCycle,
            calendarUnit: .week,
            calendarOffset: 0,
            activeWindow: activeWin,
            isBalance: provider == .deepseek,
            liveBalance: liveBal
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider == .deepseek ? "余额历史" : "配额历史")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(inlineHistorySubtitle(series: series, activeWindow: activeWin))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if provider == .antigravity, snapshot.windows.count > 1 {
                    let isThirdParty = isThirdPartyWindow(activeWin)
                    let currentKind: WindowKind = (activeWin?.kind == .fiveHour) ? .fiveHour : .weekly

                    HStack(spacing: 5) {
                        segmentedCapsule(
                            items: [("Gemini", false), ("第三方", true)],
                            selected: isThirdParty
                        ) { pickThirdParty in
                            if let target = findAntigravityWindow(thirdParty: pickThirdParty, kind: currentKind) {
                                store.popoverHistoryWindowIDs[.antigravity] = target.id
                            }
                        }

                        segmentedCapsule(
                            items: [("5h", WindowKind.fiveHour), ("7d", WindowKind.weekly)],
                            selected: currentKind
                        ) { pickKind in
                            if let target = findAntigravityWindow(thirdParty: isThirdParty, kind: pickKind) {
                                store.popoverHistoryWindowIDs[.antigravity] = target.id
                            }
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                } else if provider != .deepseek, snapshot.windows.count > 1 {
                    segmentedCapsule(
                        items: snapshot.windows.map { (shortWindowPillTitle($0), $0.id) },
                        selected: activeWin?.id ?? snapshot.windows.first?.id ?? ""
                    ) { pickedID in
                        store.popoverHistoryWindowIDs[provider] = pickedID
                    }
                }

                Button {
                    if let wid = activeWin?.id {
                        store.historyWindowID = wid
                    }
                    onOpenHistory(provider)
                } label: {
                    HStack(spacing: 3) {
                        Text("全部")
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
            }

            if let series, !series.points.isEmpty {
                Button {
                    if let wid = activeWin?.id {
                        store.historyWindowID = wid
                    }
                    onOpenHistory(provider)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Chart {
                            ForEach(series.gaps) { gap in
                                RectangleMark(
                                    xStart: .value("起点", gap.start),
                                    xEnd: .value("终点", gap.end),
                                    yStart: .value("下界", 0),
                                    yEnd: .value("上界", series.isBalanceSeries ? max(10, (series.points.map(\.value).max() ?? 50) * 1.15) : 100)
                                )
                                .foregroundStyle(Color.white.opacity(0.06))
                            }

                            ForEach(series.idealSegments) { seg in
                                LineMark(
                                    x: .value("时间", seg.start),
                                    y: .value("理想", seg.startValue),
                                    series: .value("理想线", seg.id)
                                )
                                .foregroundStyle(.white.opacity(0.38))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                                LineMark(
                                    x: .value("时间", seg.end),
                                    y: .value("理想", seg.endValue),
                                    series: .value("理想线", seg.id)
                                )
                                .foregroundStyle(.white.opacity(0.38))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            }

                            ForEach(series.points) { pt in
                                AreaMark(
                                    x: .value("时间", pt.date),
                                    y: .value("配额", pt.value),
                                    series: .value("周期面", pt.cycleID),
                                    stacking: .unstacked
                                )
                                .interpolationMethod(.monotone)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [CodexPalette.chartAccent.opacity(0.28), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                LineMark(
                                    x: .value("时间", pt.date),
                                    y: .value("配额", pt.value),
                                    series: .value("周期线", pt.cycleID)
                                )
                                .interpolationMethod(.monotone)
                                .foregroundStyle(CodexPalette.chartAccentBright)
                                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                            }

                            if let latest = series.points.last {
                                PointMark(
                                    x: .value("时间", latest.date),
                                    y: .value("配额", latest.value)
                                )
                                .foregroundStyle(CodexPalette.chartAccentBright)
                                .symbolSize(34)
                            }
                        }
                        .chartXScale(domain: series.domain)
                        .chartYScale(domain: series.isBalanceSeries
                            ? 0...max(10, (series.points.map(\.value).max() ?? 50) * 1.15)
                            : 0...100
                        )
                        .chartYAxis {
                            if series.isBalanceSeries {
                                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { val in
                                    AxisGridLine().foregroundStyle(Color.white.opacity(0.10))
                                    AxisValueLabel {
                                        if let num = val.as(Double.self) {
                                            Text(String(format: "¥%.0f", num))
                                                .font(.system(size: 9).monospacedDigit())
                                                .foregroundStyle(.white.opacity(0.56))
                                        }
                                    }
                                }
                            } else {
                                AxisMarks(position: .leading, values: [0, 50, 100]) { val in
                                    AxisGridLine().foregroundStyle(Color.white.opacity(0.10))
                                    AxisValueLabel {
                                        if let pct = val.as(Double.self) {
                                            Text("\(Int(pct))%")
                                                .font(.system(size: 9).monospacedDigit())
                                                .foregroundStyle(.white.opacity(0.56))
                                        }
                                    }
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { val in
                                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                                AxisValueLabel {
                                    if let d = val.as(Date.self) {
                                        Text(inlineAxisDateLabel(d, window: activeWin))
                                            .font(.system(size: 9).monospacedDigit())
                                            .foregroundStyle(.white.opacity(0.56))
                                    }
                                }
                            }
                        }
                        .frame(height: 118)
                        .clipped()
                        .transaction { transaction in
                            transaction.animation = nil
                        }

                        HStack(spacing: 12) {
                            ChartLegendItem(
                                kind: .actualCurve,
                                title: series.isBalanceSeries ? "余额曲线" : "实际剩余",
                                compact: true
                            )
                            if !series.idealSegments.isEmpty {
                                ChartLegendItem(
                                    kind: .idealPace,
                                    title: "理想匀速",
                                    compact: true
                                )
                            }
                            if !series.gaps.isEmpty {
                                ChartLegendItem(
                                    kind: .unrecordedGap,
                                    title: "未记录",
                                    compact: true
                                )
                            }
                            Spacer(minLength: 4)
                            if let proj = series.projectedExhaustionDate {
                                Text("预计 \(compactForecastDate(proj)) 耗尽")
                                    .foregroundStyle(CodexPalette.warningYellow)
                                    .lineLimit(1)
                            } else if let remProj = series.projectedRemainingAtReset {
                                Text("预计重置余 \(remProj)%")
                                    .foregroundStyle(.white.opacity(0.66))
                                    .lineLimit(1)
                            }
                        }
                        .font(.system(size: 10).monospacedDigit())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func inlineHistorySubtitle(series: QuotaChartSeries?, activeWindow: QuotaWindow?) -> String {
        if provider == .deepseek {
            if let bal = snapshot.preferredBalance(currencyPreference: store.preferences.deepSeekCurrencyPreference) {
                return "近 7 天 · 当前 \(bal.formattedTotal)"
            }
            return "近 7 天轨迹"
        }
        if provider == .antigravity {
            if let series {
                let prefix = series.isLowerBoundConsumption ? "≥" : ""
                return "已消耗 \(prefix)\(series.observedConsumedPercent)%"
            }
            return "当前周期"
        }
        let winLabel = activeWindow?.title ?? "当前周期"
        if let series {
            let prefix = series.isLowerBoundConsumption ? "≥" : ""
            return "\(winLabel) · 已消耗 \(prefix)\(series.observedConsumedPercent)%"
        }
        return winLabel
    }

    private func segmentedCapsule<Value: Equatable>(
        items: [(String, Value)],
        selected: Value,
        onSelect: @escaping (Value) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, pair in
                let isSel = (pair.1 == selected)
                Button {
                    onSelect(pair.1)
                } label: {
                    Text(pair.0)
                        .font(.system(size: 10.5, weight: isSel ? .semibold : .regular))
                        .foregroundStyle(isSel ? .white : .white.opacity(0.68))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 7.5)
                        .padding(.vertical, 3)
                        .background {
                            if isSel {
                                Capsule().fill(CodexPalette.chartAccent.opacity(0.34))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.08), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }

    private func isThirdPartyWindow(_ win: QuotaWindow?) -> Bool {
        guard let grp = win?.groupName?.lowercased(), !grp.isEmpty else { return false }
        return !grp.contains("gemini")
    }

    private func findAntigravityWindow(thirdParty: Bool, kind: WindowKind) -> QuotaWindow? {
        snapshot.windows.first { isThirdPartyWindow($0) == thirdParty && $0.kind == kind }
            ?? snapshot.windows.first { isThirdPartyWindow($0) == thirdParty }
            ?? snapshot.windows.first { $0.kind == kind }
    }

    private func shortWindowPillTitle(_ win: QuotaWindow) -> String {
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

    private func compactForecastDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: date)
    }

    private func inlineAxisDateLabel(_ date: Date, window: QuotaWindow?) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if (window?.durationMinutes ?? 10_080) <= 360 {
            f.dateFormat = "HH:mm"
        } else {
            f.dateFormat = "MM/dd"
        }
        return f.string(from: date)
    }

    private func miniTokenPreview(_ activity: TokenActivitySnapshot) -> some View {
        let bars = HistoryAnalytics.aggregateTokens(dailyBuckets: activity.dailyBuckets, range: .days30)
        let domain = HistoryAnalytics.tokenDomain(for: .days30, bars: bars)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Token 活动")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("30 天")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Text(CompactTokenFormatter.format(activity.last30DaysTotal))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
            }

            if !bars.isEmpty {
                Chart(bars) { item in
                    BarMark(
                        x: .value("日期", item.bucketDate, unit: .day),
                        y: .value("Token", item.tokens),
                        width: .ratio(0.74)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [CodexPalette.chartAccentBright, CodexPalette.chartAccent.opacity(0.80)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(3)
                }
                .chartXScale(domain: domain)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 82)
                .clipped()
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Settings & Footer

    private var settingsButtonRow: some View {
        Button {
            onOpenSettings()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                Text("设置")
                    .font(.subheadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footerRow: some View {
        HStack {
            if let updatedAt = snapshot.updatedAt {
                Text("更新 \(TimeFormatting.timeWithSeconds(updatedAt))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                Text("就绪")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.80))
        }
    }
}

private struct ConciseWindowRow: View {
    let window: QuotaWindow
    let now: Date
    let percentMode: QuotaPercentMode
    let lowThreshold: Int

    private var titleText: String {
        if let group = window.groupName, !group.isEmpty, !window.title.contains(group) {
            let shortGroup = group.replacingOccurrences(of: " models", with: "", options: .caseInsensitive)
            return "\(shortGroup) · \(window.title)"
        }
        return window.title
    }

    private var quotaValue: Double {
        Double(window.displayPercent(mode: percentMode))
    }

    private var timeValue: Double? {
        if let rem = window.remainingTimePercent(at: now) {
            return percentMode == .remaining ? rem : (100.0 - rem)
        }
        if window.remainingPercent == 100 && window.resetsAt == nil {
            return percentMode == .remaining ? 100.0 : 0.0
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(titleText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                paceTag
            }

            LuminousBar(
                label: percentMode == .remaining ? "剩余配额" : "已用配额",
                symbol: "battery.75percent",
                valueText: "\(Int(quotaValue.rounded()))%",
                percent: quotaValue,
                tint: CodexPalette.quotaColor(for: window.attentionLevel(at: now, criticalBelow: lowThreshold))
            )

            LuminousBar(
                label: percentMode == .remaining ? "剩余时间" : "已过时间",
                symbol: "clock",
                valueText: timeValue.map { "\(Int($0.rounded()))%" } ?? "—",
                percent: timeValue ?? 0,
                tint: CodexPalette.timeBlue
            )

            HStack {
                if let resetsAt = window.resetsAt {
                    Label(TimeFormatting.compactCountdown(until: resetsAt, from: now), systemImage: "hourglass")
                    Spacer()
                    Text(TimeFormatting.fullDateTime(resetsAt))
                        .monospacedDigit()
                } else if let raw = window.resetRawText {
                    Text(raw)
                    Spacer()
                } else if window.remainingPercent == 100 {
                    Label("未开始计时", systemImage: "hourglass")
                    Spacer()
                    Text("首次调用后起算")
                }
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.68))
        }
    }

    @ViewBuilder
    private var paceTag: some View {
        switch window.pace(at: now) {
        case .onTrack:
            Label("正常", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .overPace:
            Label("超速", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(CodexPalette.warningYellow)
        case .unavailable:
            EmptyView()
        }
    }
}

private struct LuminousBar: View {
    var label: String?
    var symbol: String? = nil
    var valueText: String?
    let percent: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            if let label, let valueText {
                HStack {
                    if let symbol {
                        Label(label, systemImage: symbol)
                    } else {
                        Text(label)
                    }
                    Spacer()
                    Text(valueText)
                        .monospacedDigit()
                        .frame(minWidth: 38, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.88))
            }

            GeometryReader { geo in
                let fraction = min(1.0, max(0.0, percent / 100.0))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                    if fraction > 0.005 {
                        Capsule()
                            .fill(tint)
                            .frame(width: max(6, geo.size.width * fraction))
                    }
                }
            }
            .frame(height: 6)
        }
    }
}
