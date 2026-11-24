import AppKit
import Charts
import SwiftUI
import UsageCenterCore

/// Dedicated popover for the clicked menu bar segment, directly matching
/// CodexMeter's clean translucent divider-separated layout and proportions.
struct ProviderDetailPopoverView: View {
    let provider: ProviderID
    @ObservedObject var store: UsageCenterStore
    let onOpenSettings: () -> Void
    let onOpenHistory: (ProviderID) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var snapshot: ProviderSnapshot {
        store.snapshot(for: provider)
    }

    private var maxScreenPopoverHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 820
        return min(780, max(520, visible - 40))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
                .layoutPriority(1)

            ScrollView {
                scrollableBody
                    .padding(.trailing, 4)
            }
            .frame(maxHeight: maxScreenPopoverHeight - 130)
            .fixedSize(horizontal: false, vertical: true)

            bottomSection
                .layoutPriority(1)
        }
        .padding(16)
        .frame(width: 386)
        .applyAppearancePreference(store.preferences.appearance)
        .onAppear {
            Task { await store.refresh(provider: provider) }
        }
    }

    // MARK: - Header (CodexMeter style)

    private var headerSection: some View {
        HStack(spacing: 10) {
            BrandBadgeView(provider: provider, size: 20, iconMode: .brand)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.headline)

                Text(snapshot.accountLabel ?? "正在检查本地账户状态…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            }
            .buttonStyle(.plain)
            .help("刷新 \(provider.displayName)")
            .disabled(store.isRefreshing(provider))
        }
    }

    // MARK: - Scrollable Sections

    private var scrollableBody: some View {
        VStack(alignment: .leading, spacing: 15) {
            if store.preferences.developerPreviewEnabled {
                HStack {
                    Label("开发者预览模式已启用", systemImage: "eye.trianglebadge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("返回实时数据") {
                        store.preferences.developerPreviewEnabled = false
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                .padding(8)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }

            if snapshot.isStale {
                Label("刷新失败，当前显示上次成功获取的缓存数据", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            if snapshot.isLoading && !snapshot.hasData {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在读取本地 \(provider.displayName) 数据…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 110)
            } else if let error = snapshot.errorMessage, !snapshot.hasData {
                VStack(alignment: .leading, spacing: 8) {
                    Label("无法读取数据", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button("重试") {
                            Task { await store.refresh(provider: provider) }
                        }
                        Button("配置 CLI…") {
                            store.selectedSettingsCategory = .cliAndAccounts
                            onOpenSettings()
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            } else {
                if let error = snapshot.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                configuredPopoverSections
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activePopoverSections: [PopoverSectionKind] {
        store.preferences.visiblePopoverSections.filter { section in
            switch section {
            case .quotaDetails:
                return snapshot.hasData
            case .quotaHistory:
                return true
            case .tokenActivity:
                return provider == .chatgpt && snapshot.tokenActivity != nil
            }
        }
    }

    private var configuredPopoverSections: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(Array(activePopoverSections.enumerated()), id: \.element.id) { idx, section in
                if idx > 0 {
                    Divider()
                }

                switch section {
                case .quotaDetails:
                    if provider == .deepseek {
                        deepSeekDetailsSection
                    } else {
                        quotaWindowsSection
                    }
                case .quotaHistory:
                    Button {
                        onOpenHistory(provider)
                    } label: {
                        popoverHistorySection
                    }
                    .buttonStyle(.plain)
                case .tokenActivity:
                    if let tokens = snapshot.tokenActivity {
                        Button {
                            onOpenHistory(provider)
                        } label: {
                            popoverTokenSection(tokens)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Quota Windows (CodexMeter UsageWindowRow + MetricBar)

    private var quotaWindowsSection: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(snapshot.windows.enumerated()), id: \.element.id) { idx, window in
                    if idx > 0 {
                        Divider()
                    }
                    CodexStyleWindowRow(
                        window: window,
                        now: context.date,
                        percentMode: store.preferences.percentMode,
                        lowThreshold: store.preferences.lowQuotaThreshold
                    )
                }
            }
        }
    }

    // MARK: - DeepSeek DSH Wallet Section

    private var deepSeekDetailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(snapshot.balances.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 {
                    Divider()
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("账户可用额度 (\(item.currency))")
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        let ok = snapshot.isAvailable ?? (item.numericTotal > 0)
                        Label(ok ? "额度正常" : "余额不足", systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(ok ? .green : .orange)
                    }

                    HStack(alignment: .lastTextBaseline) {
                        Text(item.formattedTotal)
                            .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                        Spacer()
                        Text("可用总余额")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: min(100, max(2, item.numericTotal)), total: 100)
                        .tint(item.numericTotal < 10 ? .orange : CodexPalette.timeSwiftUIColor(for: colorScheme))
                        .id(colorScheme)

                    VStack(spacing: 7) {
                        walletMetricRow(symbol: "creditcard", title: "充值余额 (Topped-up)", value: item.formattedToppedUp)
                        walletMetricRow(symbol: "gift", title: "赠送余额 (Bonus)", value: item.formattedGranted)
                        if let totalCost = item.formattedTotalCost {
                            walletMetricRow(symbol: "chart.line.uptrend.xyaxis", title: "历史累计消耗", value: totalCost)
                        }
                    }
                }
            }
        }
    }

    private func walletMetricRow(symbol: String, title: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.caption)
    }

    // MARK: - Mini Quota / Balance History Chart (CodexMeter Popover Section)

    private var popoverHistorySection: some View {
        let points = store.historyPoints(for: provider, windowID: nil, range: .currentCycle)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider == .deepseek ? "余额历史" : "配额历史")
                        .font(.subheadline.weight(.semibold))
                    Text("当前 7 天观测周期")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if provider == .deepseek, let bal = snapshot.preferredBalance(currencyPreference: store.preferences.deepSeekCurrencyPreference) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(bal.formattedTotal)
                            .font(.headline.monospacedDigit())
                        Text("当前余额")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let tightest = snapshot.mostConstrainedWindow(antigravityGroup: store.preferences.antigravityGroup) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(tightest.displayPercent(mode: store.preferences.percentMode))%")
                            .font(.headline.monospacedDigit())
                        Text("\(store.preferences.percentMode.shortVerb)配额")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if points.count >= 2 {
                CompactHistoryMiniChart(points: points, isBalance: provider == .deepseek)
                    .frame(height: 92)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundStyle(CodexPalette.chartAccent)
                    Text("已开始记录本地采样，点击打开完整历史窗口")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Mini Token Activity Section (Codex 30-day buckets)

    private func popoverTokenSection(_ activity: TokenActivitySnapshot) -> some View {
        let buckets = activity.last30DaysBuckets

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Token 活动")
                        .font(.subheadline.weight(.semibold))
                    Text("近 30 天")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !buckets.isEmpty {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(CompactTokenFormatter.format(activity.last30DaysTotal))
                            .font(.headline.monospacedDigit())
                        Text("总 Token")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !buckets.isEmpty {
                Chart(buckets) { item in
                    BarMark(
                        x: .value("日期", item.startDate),
                        y: .value("Token", item.tokens)
                    )
                    .foregroundStyle(CodexPalette.chartAccentBright.gradient)
                    .cornerRadius(2)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 88)
            } else if let lifetime = activity.lifetimeTokens {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(CodexPalette.chartAccent)
                    Text("累计消耗 \(CompactTokenFormatter.format(lifetime)) Tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bottom Settings & Footer (CodexMeter exact layout)

    private var bottomSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            Button {
                onOpenSettings()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "gearshape")
                    Text("设置")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            HStack {
                if let updatedAt = snapshot.updatedAt {
                    Text("已更新 \(TimeFormatting.timeWithSeconds(updatedAt))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                } else {
                    Text("本地 CLI 连接就绪")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - CodexMeter-style Window Row & MetricBar

private struct CodexStyleWindowRow: View {
    let window: QuotaWindow
    let now: Date
    let percentMode: QuotaPercentMode
    let lowThreshold: Int
    @Environment(\.colorScheme) private var colorScheme

    private var displayTitle: String {
        if let group = window.groupName, !group.isEmpty, !window.title.contains(group) {
            return "\(group) · \(window.title)"
        }
        return window.title
    }

    private var quotaValue: Double {
        Double(window.displayPercent(mode: percentMode))
    }

    private var timeValue: Double? {
        guard let remTime = window.remainingTimePercent(at: now) else { return nil }
        return percentMode == .remaining ? remTime : (100.0 - remTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayTitle)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                paceIndicator
            }

            CodexMetricBar(
                label: percentMode == .remaining ? "剩余配额" : "已用配额",
                value: quotaValue,
                tint: CodexPalette.quotaSwiftUIColor(
                    for: window.attentionLevel(at: now, criticalBelow: lowThreshold),
                    colorScheme: colorScheme
                ),
                symbol: "battery.75percent"
            )

            CodexMetricBar(
                label: percentMode == .remaining ? "剩余时间" : "已过时间",
                value: timeValue,
                tint: CodexPalette.timeSwiftUIColor(for: colorScheme),
                symbol: "clock"
            )

            HStack {
                if let resetsAt = window.resetsAt {
                    Label(TimeFormatting.detailedCountdown(until: resetsAt, from: now), systemImage: "hourglass")
                } else if let raw = window.resetRawText {
                    Label("重置：\(raw)", systemImage: "hourglass")
                } else {
                    Label("重置时间不可用", systemImage: "hourglass")
                }

                Spacer()

                if let resetsAt = window.resetsAt {
                    Text("重置：\(TimeFormatting.fullDateTime(resetsAt))")
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var paceIndicator: some View {
        switch window.pace(at: now) {
        case .onTrack:
            Label("进度正常", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .overPace:
            Label("超出进度", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case .unavailable:
            Label("未知进度", systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CodexMetricBar: View {
    let label: String
    let value: Double?
    let tint: Color
    let symbol: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Label(label, systemImage: symbol)
                Spacer()
                Text(value.map { "\(Int($0.rounded()))%" } ?? "—")
                    .monospacedDigit()
            }
            .font(.caption)

            ProgressView(value: value ?? 0, total: 100)
                .tint(tint)
                .id(colorScheme)
                .opacity(value == nil ? 0.25 : 1)
        }
    }
}

struct CompactHistoryMiniChart: View {
    let points: [QuotaHistoryPoint]
    let isBalance: Bool

    var body: some View {
        Chart {
            ForEach(points) { pt in
                let yVal = isBalance ? (pt.balanceAmount ?? 0) : Double(pt.remainingPercent)
                AreaMark(
                    x: .value("时间", pt.timestamp),
                    y: .value("数值", yVal)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [CodexPalette.chartAccent.opacity(0.24), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("时间", pt.timestamp),
                    y: .value("数值", yVal)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(CodexPalette.chartAccentBright)
                .lineStyle(StrokeStyle(lineWidth: 1.4))
            }

            if let latest = points.last {
                let yVal = isBalance ? (latest.balanceAmount ?? 0) : Double(latest.remainingPercent)
                PointMark(
                    x: .value("时间", latest.timestamp),
                    y: .value("数值", yVal)
                )
                .foregroundStyle(CodexPalette.chartAccentBright)
                .symbolSize(28)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}
