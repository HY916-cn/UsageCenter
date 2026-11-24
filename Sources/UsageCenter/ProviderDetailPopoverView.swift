import AppKit
import SwiftUI
import UsageCenterCore

struct ProviderDetailPopoverView: View {
    @ObservedObject var store: UsageCenterStore
    let onOpenSettings: () -> Void
    let onClosePopover: () -> Void

    private var activeProvider: ProviderID {
        store.activeProvider
    }

    private var snapshot: ProviderSnapshot {
        store.snapshot(for: activeProvider)
    }

    private var accentColor: Color {
        BrandIconRenderer.swiftUIAccent(for: activeProvider)
    }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { timeline in
            ZStack {
                LiquidBackdrop(accent: accentColor)

                VStack(alignment: .leading, spacing: 12) {
                    providerSwitcherBar
                    heroHeaderCard

                    ScrollView {
                        LiquidGlassStage(spacing: 12) {
                            VStack(alignment: .leading, spacing: 12) {
                                detailBody(now: timeline.date)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 430)
                    .fixedSize(horizontal: false, vertical: true)

                    footerBar
                }
                .padding(14)
            }
        }
        .frame(width: 392)
        .applyAppearancePreference(store.preferences.appearance)
    }

    // MARK: - Switcher Bar

    private var providerSwitcherBar: some View {
        let items = store.preferences.enabledSections.isEmpty
            ? ProviderID.allCases
            : store.preferences.enabledSections.map(\.provider)

        return HStack(spacing: 6) {
            ForEach(items) { provider in
                let isSelected = (provider == activeProvider)
                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                        store.activeProvider = provider
                    }
                } label: {
                    HStack(spacing: 5) {
                        BrandBadgeView(
                            provider: provider,
                            size: 14,
                            iconMode: store.preferences.iconColorMode
                        )
                        Text(provider.displayName)
                            .font(.caption.weight(isSelected ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(BrandIconRenderer.swiftUIAccent(for: provider).opacity(0.20))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .padding(4)
        .liquidGlassCapsule()
    }

    // MARK: - Hero Card

    private var heroHeaderCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.16))
                    .frame(width: 40, height: 40)
                BrandBadgeView(provider: activeProvider, size: 22, iconMode: .brand)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(activeProvider.displayName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))

                    if snapshot.isStale {
                        Text("缓存数据")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.14), in: Capsule())
                    }
                }

                Text(snapshot.accountLabel ?? activeProvider.cliMethodSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await store.refresh(provider: activeProvider) }
            } label: {
                Group {
                    if snapshot.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .frame(width: 28, height: 28)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .liquidGlassCapsule(interactive: true)
            .help("刷新 \(activeProvider.displayName)")
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: 16)
    }

    // MARK: - Main Content

    @ViewBuilder
    private func detailBody(now: Date) -> some View {
        if snapshot.isLoading && !snapshot.hasData {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在通过本地 CLI 读取 \(activeProvider.displayName) 数据…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(14)
            .liquidGlassCard(cornerRadius: 16)
        } else if activeProvider == .deepseek {
            deepSeekDetailSection
        } else {
            quotaDetailSection(now: now)
        }
    }

    @ViewBuilder
    private func quotaDetailSection(now: Date) -> some View {
        if let err = snapshot.errorMessage {
            errorNoticeCard(err)
        }

        if !snapshot.windows.isEmpty {
            let grouped = groupedQuotaWindows(snapshot.windows)
            ForEach(grouped, id: \.title) { group in
                VStack(alignment: .leading, spacing: 12) {
                    if let headerTitle = group.header {
                        HStack {
                            Text(headerTitle)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(accentColor)
                            Spacer()
                            Text("共享 5h 与周限额")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(Array(group.windows.enumerated()), id: \.element.id) { idx, window in
                        if idx > 0 {
                            Divider().opacity(0.35)
                        }
                        QuotaWindowDetailRow(
                            window: window,
                            now: now,
                            percentMode: store.preferences.percentMode,
                            accent: accentColor
                        )
                    }
                }
                .padding(14)
                .liquidGlassCard(cornerRadius: 16)
            }
        }
    }

    @ViewBuilder
    private var deepSeekDetailSection: some View {
        if let err = snapshot.errorMessage {
            errorNoticeCard(err)
        }

        if !snapshot.balances.isEmpty {
            ForEach(snapshot.balances) { item in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("API 账户总余额 (\(item.currency))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.formattedTotal)
                                .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(accentColor)
                        }

                        Spacer()

                        let available = snapshot.isAvailable ?? (item.numericTotal > 0)
                        Label(available ? "服务可用" : "余额不足", systemImage: available ? "checkmark.seal.fill" : "xmark.octagon.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(available ? .green : .red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((available ? Color.green : Color.red).opacity(0.14), in: Capsule())
                    }

                    HStack(spacing: 10) {
                        balanceBreakdownPill(
                            title: "充值余额 (Topped-up)",
                            value: "\(item.currencySymbol)\(item.toppedUpBalance)"
                        )
                        balanceBreakdownPill(
                            title: "赠送余额 (Granted)",
                            value: "\(item.currencySymbol)\(item.grantedBalance)"
                        )
                    }
                }
                .padding(14)
                .liquidGlassCard(cornerRadius: 16)
            }
        }

        if !store.hasStoredDeepSeekKey && store.preferences.deepSeekCustomCommand.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Label("快捷配置 DeepSeek API Key", systemImage: "key.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)

                Text("密钥仅保存在 macOS 系统钥匙串中，并通过本地 curl 标准输入安全请求余额接口。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    SecureField("粘贴 sk-... API Key", text: $store.deepSeekAPIKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    Button("保存并查询") {
                        store.saveDeepSeekKey()
                    }
                    .controlSize(.small)
                    .disabled(store.deepSeekAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(14)
            .liquidGlassCard(cornerRadius: 16)
        }
    }

    private func balanceBreakdownPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func errorNoticeCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("CLI 数据读取提示", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("重试") {
                    Task { await store.refresh(provider: activeProvider) }
                }
                .controlSize(.small)

                Button("打开 CLI 设置…") {
                    store.selectedSettingsTab = .cli
                    onOpenSettings()
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlassCard(cornerRadius: 16)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                if let updatedAt = snapshot.updatedAt {
                    Text("更新于 \(TimeFormatting.timeWithSeconds(updatedAt))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("本地 CLI 实时驱动")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task { await store.refreshAll() }
            } label: {
                Label("全部刷新", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Divider().frame(height: 12)

            Button {
                onOpenSettings()
            } label: {
                Label("设置", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            Divider().frame(height: 12)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("退出")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassCapsule()
    }

    private struct WindowGroupBucket {
        let title: String
        let header: String?
        let windows: [QuotaWindow]
    }

    private func groupedQuotaWindows(_ windows: [QuotaWindow]) -> [WindowGroupBucket] {
        var order: [String] = []
        var map: [String: [QuotaWindow]] = [:]
        for win in windows {
            let key = win.groupName ?? "__default__"
            if map[key] == nil {
                order.append(key)
                map[key] = []
            }
            map[key]?.append(win)
        }
        let showHeader = order.count > 1 || (order.first != nil && order.first != "__default__")
        return order.map { key in
            WindowGroupBucket(
                title: key,
                header: (showHeader && key != "__default__") ? key : nil,
                windows: map[key] ?? []
            )
        }
    }
}

private struct QuotaWindowDetailRow: View {
    let window: QuotaWindow
    let now: Date
    let percentMode: QuotaPercentMode
    let accent: Color

    var body: some View {
        let primaryPct = window.displayPercent(mode: percentMode)
        let secondaryPct = percentMode == .used ? window.remainingPercent : window.usedPercent
        let secondaryVerb = percentMode == .used ? "剩余" : "已用"

        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                paceBadge
            }

            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(percentMode.shortVerb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(primaryPct)%")
                        .font(.system(size: 21, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(barTint)
                }

                Spacer()

                Text("\(secondaryVerb) \(secondaryPct)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            LiquidProgressTrack(
                label: percentMode == .used ? "已消耗配额" : "剩余可用配额",
                percent: Double(primaryPct),
                tint: barTint
            )

            if let timePct = (percentMode == .used ? window.elapsedTimePercent(at: now) : window.remainingTimePercent(at: now)) {
                LiquidProgressTrack(
                    label: percentMode == .used ? "周期已过时间" : "周期剩余时间",
                    percent: timePct,
                    tint: .cyan.opacity(0.85)
                )
            }

            HStack {
                if let resetsAt = window.resetsAt {
                    Label(TimeFormatting.detailedCountdown(until: resetsAt, from: now), systemImage: "hourglass")
                    Spacer()
                    Text("重置于 \(TimeFormatting.fullDateTime(resetsAt))")
                        .monospacedDigit()
                } else if let raw = window.resetRawText {
                    Label("重置：\(raw)", systemImage: "clock")
                    Spacer()
                } else {
                    Label("重置时间未知", systemImage: "clock")
                    Spacer()
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var barTint: Color {
        switch window.attentionLevel(at: now) {
        case .critical:
            return .red
        case .warning:
            return .orange
        case .normal:
            return accent
        }
    }

    @ViewBuilder
    private var paceBadge: some View {
        if window.remainingPercent <= 20 {
            Label("额度紧张", systemImage: "bolt.trianglebadge.exclamationmark.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.red.opacity(0.14), in: Capsule())
        } else {
            switch window.pace(at: now) {
            case .onTrack:
                Label("进度健康", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.14), in: Capsule())
            case .overPace:
                Label("消耗偏快", systemImage: "flame.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.14), in: Capsule())
            case .unavailable:
                EmptyView()
            }
        }
    }
}

private struct LiquidProgressTrack: View {
    let label: String
    let percent: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(percent.rounded()))%")
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            GeometryReader { geo in
                let clamped = min(1.0, max(0.0, percent / 100.0))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.10))
                    if clamped > 0.005 {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.85), tint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(6, geo.size.width * clamped))
                    }
                }
            }
            .frame(height: 6.5)
        }
    }
}
