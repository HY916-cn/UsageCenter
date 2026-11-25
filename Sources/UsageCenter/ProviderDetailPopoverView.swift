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
        .frame(width: 376)
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

            if store.isRefreshing(provider) {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await store.refresh(provider: provider) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
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
                        Button {
                            onOpenHistory(provider)
                        } label: {
                            miniHistoryPreview
                        }
                        .buttonStyle(.plain)
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

    // MARK: - Mini History & Token Previews

    private var miniHistoryPreview: some View {
        let samples = store.windowSamples(for: provider, windowID: nil)
        let activeWin = store.activeWindowObject(for: provider, windowID: nil)
        let series = HistoryAnalytics.buildQuotaSeries(
            samples: samples,
            mode: .currentCycle,
            calendarUnit: .week,
            calendarOffset: 0,
            activeWindow: activeWin,
            isBalance: provider == .deepseek
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider == .deepseek ? "余额历史" : "配额历史")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("当前周期")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                if provider == .deepseek, let bal = snapshot.preferredBalance(currencyPreference: store.preferences.deepSeekCurrencyPreference) {
                    Text(bal.formattedTotal)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                } else if let w = activeWin {
                    Text("\(w.displayPercent(mode: store.preferences.percentMode))%")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
            }

            if let series, series.points.count >= 2 {
                Chart {
                    ForEach(series.idealSegments) { seg in
                        LineMark(
                            x: .value("时间", seg.start),
                            y: .value("理想", seg.startValue),
                            series: .value("理想线", seg.id)
                        )
                        .foregroundStyle(.white.opacity(0.32))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        LineMark(
                            x: .value("时间", seg.end),
                            y: .value("理想", seg.endValue),
                            series: .value("理想线", seg.id)
                        )
                        .foregroundStyle(.white.opacity(0.32))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }

                    ForEach(series.points) { pt in
                        AreaMark(
                            x: .value("时间", pt.date),
                            y: .value("配额", pt.value),
                            series: .value("周期", pt.cycleID)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [CodexPalette.chartAccent.opacity(0.26), .clear],
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
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                    }
                }
                .chartXScale(domain: series.domain)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 82)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundStyle(CodexPalette.chartAccentBright)
                    Text("点击查看详细历史分析")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
                }
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
    }

    private func miniTokenPreview(_ activity: TokenActivitySnapshot) -> some View {
        let bars = HistoryAnalytics.aggregateTokens(dailyBuckets: activity.dailyBuckets, range: .days30)

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
                        x: .value("日期", item.bucketDate),
                        y: .value("Token", item.tokens)
                    )
                    .foregroundStyle(CodexPalette.chartAccentBright.gradient)
                    .cornerRadius(2)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 76)
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
        guard let rem = window.remainingTimePercent(at: now) else { return nil }
        return percentMode == .remaining ? rem : (100.0 - rem)
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
