import AppKit
import Charts
import SwiftUI
import UsageCenterCore

/// Full-size Liquid Glass Usage History window matching CodexMeter's UsageHistoryView.
struct UsageHistoryWindowView: View {
    @ObservedObject var store: UsageCenterStore

    private var activeProvider: ProviderID {
        store.historyProvider
    }

    private var snapshot: ProviderSnapshot {
        store.snapshot(for: activeProvider)
    }

    private var filteredPoints: [QuotaHistoryPoint] {
        store.historyPoints(
            for: activeProvider,
            windowID: store.historyWindowID,
            range: store.historyRange
        )
    }

    var body: some View {
        ZStack {
            HistoryBackdrop()
            mainLayout
        }
        .frame(minWidth: 720, idealWidth: 900, minHeight: 600, idealHeight: 800)
        .applyAppearancePreference(store.preferences.appearance)
    }

    @ViewBuilder
    private var mainLayout: some View {
        if #available(macOS 26.0, *) {
            scrollContent
                .safeAreaBar(edge: .top, spacing: 0) {
                    topHeader
                }
        } else {
            scrollContent
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        topHeader
                        Divider().opacity(0.4)
                    }
                    .background(.ultraThinMaterial)
                }
        }
    }

    private var topHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("用量历史")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("本地记录的各服务配额变化曲线与 Token 消耗活动")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(ProviderID.allCases) { p in
                    let selected = (p == activeProvider)
                    Button {
                        store.historyProvider = p
                        store.historyWindowID = store.defaultHistoryWindowID(for: p)
                    } label: {
                        HStack(spacing: 5) {
                            BrandBadgeView(provider: p, size: 14, iconMode: .brand)
                            Text(p.displayName)
                                .font(.caption.weight(selected ? .semibold : .regular))
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .background {
                            if selected {
                                Capsule().fill(CodexPalette.chartAccent.opacity(0.22))
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected ? CodexPalette.chartAccentBright : .secondary)
                }
            }
            .padding(4)
            .background(.secondary.opacity(0.09), in: Capsule())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var scrollContent: some View {
        ScrollView {
            cardContainer
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 26)
        }
    }

    @ViewBuilder
    private var cardContainer: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                cardsStack
            }
        } else {
            cardsStack
        }
    }

    private var cardsStack: some View {
        VStack(alignment: .leading, spacing: 18) {
            quotaHistoryCard

            if activeProvider == .chatgpt, let tokenActivity = snapshot.tokenActivity {
                tokenActivityCard(tokenActivity)
            }

            storageSummaryCard
        }
    }

    private var quotaHistoryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(activeProvider == .deepseek ? "API 余额变化趋势" : "配额周期曲线")
                        .font(.title3.weight(.bold))
                    Text(store.historyRange.localizedName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if activeProvider != .deepseek, snapshot.windows.count > 1 {
                    Picker("窗口", selection: Binding(
                        get: { store.historyWindowID ?? store.defaultHistoryWindowID(for: activeProvider) },
                        set: { store.historyWindowID = $0 }
                    )) {
                        ForEach(snapshot.windows) { win in
                            let label = win.groupName.map { "\($0) · \(win.title)" } ?? win.title
                            Text(label).tag(Optional(win.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 230)
                }
            }

            rangeCapsulePicker

            if filteredPoints.count >= 2 {
                HStack(alignment: .lastTextBaseline, spacing: 24) {
                    if activeProvider == .deepseek {
                        let latest = filteredPoints.last?.balanceAmount ?? 0
                        headlineMetric(title: "当前可用余额", value: String(format: "¥%.2f", latest), tint: CodexPalette.chartAccentBright)
                    } else {
                        let latest = filteredPoints.last?.remainingPercent ?? 0
                        headlineMetric(title: "当前剩余配额", value: "\(latest)%", tint: CodexPalette.chartAccentBright)
                    }
                    headlineMetric(title: "采样记录点", value: "\(filteredPoints.count)", tint: .primary)
                    Spacer()
                }

                Chart {
                    ForEach(filteredPoints) { pt in
                        let yVal = activeProvider == .deepseek ? (pt.balanceAmount ?? 0) : Double(pt.remainingPercent)
                        AreaMark(
                            x: .value("时间", pt.timestamp),
                            y: .value("数值", yVal)
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
                            x: .value("时间", pt.timestamp),
                            y: .value("数值", yVal)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(CodexPalette.chartAccentBright)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    }

                    if let last = filteredPoints.last {
                        let yVal = activeProvider == .deepseek ? (last.balanceAmount ?? 0) : Double(last.remainingPercent)
                        PointMark(
                            x: .value("时间", last.timestamp),
                            y: .value("数值", yVal)
                        )
                        .foregroundStyle(CodexPalette.chartAccentBright)
                        .symbolSize(40)
                    }
                }
                .frame(height: 260)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2)
                        .foregroundStyle(CodexPalette.chartAccent)
                    Text("历史采样积累中")
                        .font(.headline)
                    Text("UsageCenter 会在后台每次配额变化及每 15 分钟自动记录锚点；也可在设置 → 开发者选项中生成演示数据预览图表。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
                .frame(maxWidth: .infinity, minHeight: 190)
            }
        }
        .padding(22)
        .liquidHistoryCard(cornerRadius: 22)
    }

    private func tokenActivityCard(_ activity: TokenActivitySnapshot) -> some View {
        let buckets = activity.last30DaysBuckets

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Token 活动 (ChatGPT / Codex)")
                    .font(.title3.weight(.bold))
                Text("近 30 天每日消耗统计")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                headlineMetric(
                    title: "近 30 天总计",
                    value: CompactTokenFormatter.format(activity.last30DaysTotal),
                    tint: CodexPalette.chartAccentBright
                )
                if let peak = activity.peakDailyTokens {
                    headlineMetric(
                        title: "单日峰值",
                        value: CompactTokenFormatter.format(peak),
                        tint: .primary
                    )
                }
                if let lifetime = activity.lifetimeTokens {
                    headlineMetric(
                        title: "历史总计",
                        value: CompactTokenFormatter.format(lifetime),
                        tint: .primary
                    )
                }
                Spacer()
            }

            if !buckets.isEmpty {
                Chart(buckets) { item in
                    BarMark(
                        x: .value("日期", item.startDate),
                        y: .value("Tokens", item.tokens)
                    )
                    .foregroundStyle(CodexPalette.chartAccentBright.gradient)
                    .cornerRadius(3)
                }
                .chartXAxis(.hidden)
                .frame(height: 200)
            }
        }
        .padding(22)
        .liquidHistoryCard(cornerRadius: 22)
    }

    private var storageSummaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("本地历史存储")
                    .font(.headline)
                Text("当前占用 \(ByteCountFormatter.string(fromByteCount: store.historyStorageBytes, countStyle: .file)) · 仅保存在本机 Application Support 目录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("导出 CSV…") {
                store.exportHistoryCSVInteractive()
            }
        }
        .padding(20)
        .liquidHistoryCard(cornerRadius: 22)
    }

    private var rangeCapsulePicker: some View {
        HStack(spacing: 5) {
            ForEach(HistoryTimeRange.allCases) { option in
                let selected = (store.historyRange == option)
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        store.historyRange = option
                    }
                } label: {
                    Text(option.localizedName)
                        .font(.caption.weight(selected ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background {
                            if selected {
                                Capsule().fill(CodexPalette.chartAccent.opacity(0.20))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? CodexPalette.chartAccentBright : .secondary)
            }
        }
        .padding(4)
        .background(.secondary.opacity(0.08), in: Capsule())
    }

    private func headlineMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
        }
    }
}
