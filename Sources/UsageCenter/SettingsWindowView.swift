import AppKit
import SwiftUI
import UsageCenterCore

/// Native macOS 27 Liquid Glass Settings Window with guaranteed single-click sidebar navigation.
struct SettingsWindowView: View {
    @ObservedObject var store: UsageCenterStore
    let onOpenHistory: (ProviderID) -> Void

    var body: some View {
        ZStack {
            HistoryBackdrop()

            HStack(spacing: 16) {
                sidebarRail
                detailPanel
            }
            .padding(.horizontal, 18)
            .padding(.top, 38)
            .padding(.bottom, 18)
        }
        .frame(minWidth: 800, idealWidth: 860, minHeight: 620, idealHeight: 680)
        .applyDarkLiquidGlassTheme()
        .onAppear {
            store.refreshLaunchAtLoginStatus()
            store.refreshDSHLoginStatus()
            store.reloadHistoryMetadata()
        }
        .alert("确认清空本地历史？", isPresented: $store.showsClearHistoryAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                store.clearHistory()
            }
        } message: {
            Text("已记录的配额和余额历史将无法恢复。")
        }
    }

    // MARK: - Interactive Liquid Glass Sidebar Rail

    private var sidebarRail: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                BrandBadgeView(provider: .antigravity, size: 17)
                Text("UsageCenter")
                    .font(.headline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            ForEach(SettingsCategory.allCases) { category in
                let isSelected = (store.selectedSettingsCategory == category)
                Button {
                    store.selectedSettingsCategory = category
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: category.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 18)
                        Text(category.title)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        Spacer()
                    }
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.72))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.16))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(10)
        .frame(width: 196)
        .frame(maxHeight: .infinity)
        .liquidGlassSurface(cornerRadius: 20)
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    if let msg = store.statusBannerMessage {
                        HStack {
                            Label(msg, systemImage: "info.circle.fill")
                                .font(.caption)
                            Spacer()
                            Button("关闭") { store.statusBannerMessage = nil }
                                .buttonStyle(.plain)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(12)
                        .liquidGlassSurface(cornerRadius: 14)
                    }

                    switch store.selectedSettingsCategory {
                    case .menuAndPopover:
                        menuAndPopoverPage
                    case .cliAndAccounts:
                        cliAndAccountsPage
                    case .general:
                        generalPage
                    case .notifications:
                        notificationsPage
                    case .history:
                        historyPage
                    case .developer:
                        developerPage
                    case .about:
                        aboutPage
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 1. Menu Bar & Popover

    @ViewBuilder
    private var menuAndPopoverPage: some View {
        glassCard("实时预览") {
            HStack {
                Spacer()
                Image(nsImage: StatusSegmentRenderer.renderCompositePreviewImage(
                    preferences: store.preferences,
                    snapshots: store.snapshots
                ))
                .interpolation(.high)
                Spacer()
            }
            .frame(minHeight: 40)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }

        glassCard("菜单栏样式") {
            settingPickerRow("默认样式", selection: $store.preferences.globalStyle) {
                ForEach(SegmentDisplayStyle.allCases) { Text($0.localizedName).tag($0) }
            }
            settingPickerRow("百分比模式", selection: $store.preferences.percentMode) {
                ForEach(QuotaPercentMode.allCases) { Text($0.localizedName).tag($0) }
            }
            settingPickerRow("下标内容", selection: $store.preferences.timeDisplayMode) {
                ForEach(TimeDisplayMode.allCases) { Text($0.localizedName).tag($0) }
            }
            HStack(spacing: 24) {
                Toggle("显示分隔竖线", isOn: $store.preferences.showsDividers)
                Toggle("等宽数字", isOn: $store.preferences.monospacedDigits)
            }
            .font(.subheadline)
        }

        glassCard("各部分显示与顺序") {
            ForEach(Array(store.preferences.sections.enumerated()), id: \.element.provider) { idx, section in
                if idx > 0 {
                    Divider().overlay(Color.white.opacity(0.12))
                }
                providerRow(section: section, index: idx, total: store.preferences.sections.count)
            }
        }

        glassCard("弹窗模块与顺序") {
            ForEach(Array(store.preferences.popoverSections.enumerated()), id: \.element.id) { idx, kind in
                HStack(spacing: 10) {
                    Toggle(
                        kind.localizedName,
                        isOn: Binding(
                            get: { store.preferences.isPopoverSectionVisible(kind) },
                            set: { store.preferences.setPopoverSection(kind, visible: $0) }
                        )
                    )
                    Spacer()
                    Button {
                        store.preferences.movePopoverSection(kind, by: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(idx == 0)

                    Button {
                        store.preferences.movePopoverSection(kind, by: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(idx >= store.preferences.popoverSections.count - 1)
                }
            }

            HStack {
                Button("恢复默认设置") {
                    store.restoreDefaultPreferences()
                }
                .buttonStyle(.glass)
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func providerRow(section: ProviderSectionConfig, index: Int, total: Int) -> some View {
        let provider = section.provider
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                BrandBadgeView(provider: provider, size: 15)
                Text(provider.displayName)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    store.preferences.moveSection(provider, by: -1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)

                Button {
                    store.preferences.moveSection(provider, by: 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(index >= total - 1)

                Toggle("", isOn: Binding(
                    get: { section.isEnabled },
                    set: { val in store.preferences.updateSection(provider) { $0.isEnabled = val } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if section.isEnabled {
                HStack(spacing: 12) {
                    Picker("样式", selection: Binding<SegmentDisplayStyle?>(
                        get: { section.styleOverride },
                        set: { val in store.preferences.updateSection(provider) { $0.styleOverride = val } }
                    )) {
                        Text("跟随全局").tag(SegmentDisplayStyle?.none)
                        ForEach(SegmentDisplayStyle.allCases) { s in
                            Text(s.localizedName).tag(Optional(s))
                        }
                    }
                    .controlSize(.small)
                    .frame(maxWidth: 180)

                    if provider.isQuotaProvider {
                        Picker("窗口", selection: Binding(
                            get: { section.windowVisibility },
                            set: { val in store.preferences.updateSection(provider) { $0.windowVisibility = val } }
                        )) {
                            ForEach(WindowVisibilityMode.allCases) { m in
                                Text(m.localizedName).tag(m)
                            }
                        }
                        .controlSize(.small)
                        .frame(maxWidth: 150)
                    } else {
                        Picker("币种", selection: $store.preferences.deepSeekCurrencyPreference) {
                            Text("自动").tag("AUTO")
                            Text("CNY").tag("CNY")
                            Text("USD").tag("USD")
                        }
                        .controlSize(.small)
                        .frame(maxWidth: 130)
                    }

                    if provider == .antigravity {
                        Picker("模型组", selection: $store.preferences.antigravityGroup) {
                            ForEach(AntigravityGroupPreference.allCases) { g in
                                Text(g.localizedName).tag(g)
                            }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.leading, 25)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - 2. CLI & Accounts

    @ViewBuilder
    private var cliAndAccountsPage: some View {
        glassCard("DeepSeek (DSH 本地账户)") {
            HStack {
                Text("登录状态")
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                if store.hasDSHLocalLogin {
                    Label("已读取 ~/.dsh/.credentials.yaml", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("未检测到 DSH 登录", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(CodexPalette.warningYellow)
                }
            }

            if let bal = store.snapshot(for: .deepseek).preferredBalance(currencyPreference: store.preferences.deepSeekCurrencyPreference) {
                HStack {
                    Text("当前余额")
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Text("\(bal.formattedTotal)（充值 \(bal.formattedToppedUp) / 赠送 \(bal.formattedGranted)）")
                        .font(.subheadline.monospacedDigit())
                }
            }

            HStack {
                Button("刷新 DSH 额度") {
                    Task { await store.refresh(provider: .deepseek) }
                }
                .buttonStyle(.glass)
                Spacer()
            }
        }

        glassCard("本地 CLI 路径") {
            ForEach([ProviderID.claude, .chatgpt, .antigravity]) { provider in
                let detected = store.detectedCLIPath(for: provider)
                let cfg = store.preferences.config(for: provider)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        BrandBadgeView(provider: provider, size: 14)
                        Text(provider.displayName)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if let detected {
                            Text(detected)
                                .font(.caption.monospaced())
                                .foregroundStyle(.green)
                        } else {
                            Text("未找到 \(provider.defaultBinaryName)")
                                .font(.caption)
                                .foregroundStyle(CodexPalette.warningYellow)
                        }
                        Button("刷新") {
                            Task { await store.refresh(provider: provider) }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }

                    TextField(
                        "自定义路径（留空自动检测）",
                        text: Binding(
                            get: { cfg.customCLIPath },
                            set: { val in store.preferences.updateSection(provider) { $0.customCLIPath = val } }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                }
                .padding(.vertical, 4)
            }
        }

        glassCard("备用 DeepSeek Key / CLI") {
            HStack(spacing: 8) {
                SecureField("备用 API Key（未登录 DSH 时生效）", text: $store.deepSeekAPIKeyInput)
                    .textFieldStyle(.roundedBorder)
                Button("保存") {
                    store.saveDeepSeekKey()
                }
                .buttonStyle(.glass)
                if store.hasStoredDeepSeekKey {
                    Button("清除") {
                        store.clearDeepSeekKey()
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    // MARK: - 3. General

    private var generalPage: some View {
        glassCard("刷新与启动") {
            settingPickerRow("后台刷新频率", selection: $store.preferences.refreshIntervalSeconds) {
                Text("30 秒").tag(30)
                Text("60 秒（默认）").tag(60)
                Text("2 分钟").tag(120)
                Text("5 分钟").tag(300)
                Text("仅手动").tag(0)
            }

            Toggle("登录 macOS 时自动启动", isOn: Binding(
                get: { store.launchAtLoginEnabled },
                set: { store.setLaunchAtLogin($0) }
            ))
        }
    }

    // MARK: - 4. Notifications

    private var notificationsPage: some View {
        glassCard("配额提醒") {
            Toggle("启用本地通知提醒", isOn: Binding(
                get: { store.preferences.notificationsEnabled },
                set: { store.setNotificationsEnabled($0) }
            ))

            Stepper(
                "低配额阈值：剩余低于 \(store.preferences.lowQuotaThreshold)%",
                value: $store.preferences.lowQuotaThreshold,
                in: 5...50,
                step: 5
            )

            Toggle("消耗超速时提醒", isOn: $store.preferences.notifyOnOverPace)
        }
    }

    // MARK: - 5. History

    private var historyPage: some View {
        glassCard("历史记录管理") {
            settingPickerRow("保留周期", selection: $store.preferences.historyRetention) {
                ForEach(HistoryRetentionPolicy.allCases) { Text($0.localizedName).tag($0) }
            }

            HStack {
                Text("存储占用")
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("\(ByteCountFormatter.string(fromByteCount: store.historyStorageBytes, countStyle: .file)) · \(store.historySamples.count) 条")
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                Button("打开用量历史") {
                    onOpenHistory(store.activeProvider)
                }
                .buttonStyle(.glass)

                Button("导出 CSV") {
                    store.exportHistoryCSVInteractive()
                }
                .buttonStyle(.glass)
                .disabled(store.historySamples.isEmpty)

                Button("清空历史") {
                    store.showsClearHistoryAlert = true
                }
                .buttonStyle(.glass)
                .disabled(store.historySamples.isEmpty)
            }
        }
    }

    // MARK: - 6. Developer

    private var developerPage: some View {
        glassCard("开发者预览") {
            Toggle("菜单栏模拟预览", isOn: $store.preferences.developerPreviewEnabled)

            HStack {
                Text("剩余配额 \(Int(store.preferences.developerPreviewRemaining.rounded()))%")
                    .frame(width: 120, alignment: .leading)
                Slider(value: $store.preferences.developerPreviewRemaining, in: 0...100, step: 1)
            }

            HStack {
                Text("剩余时间 \(Int(store.preferences.developerPreviewTimeRemaining.rounded()))%")
                    .frame(width: 120, alignment: .leading)
                Slider(value: $store.preferences.developerPreviewTimeRemaining, in: 0...100, step: 1)
            }

            HStack(spacing: 10) {
                Button("生成 14 天多周期演示历史") {
                    store.generateDemoHistory()
                }
                .buttonStyle(.glass)

                Button("清空演示历史") {
                    store.clearHistory()
                }
                .buttonStyle(.glass)
            }
        }
    }

    // MARK: - 7. About

    private var aboutPage: some View {
        glassCard("关于 UsageCenter") {
            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    BrandBadgeView(provider: .claude, size: 20)
                    BrandBadgeView(provider: .chatgpt, size: 20)
                    BrandBadgeView(provider: .antigravity, size: 20)
                    BrandBadgeView(provider: .deepseek, size: 20)
                }
                .padding(10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("UsageCenter 1.2.0")
                        .font(.title3.weight(.bold))
                    Text("Claude · ChatGPT · Antigravity · DeepSeek (DSH)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
                    Link("https://github.com/HY916-cn/UsageCenter",
                         destination: URL(string: "https://github.com/HY916-cn/UsageCenter")!)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Card & Row Builders

    private func glassCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassSurface(cornerRadius: 20)
    }

    private func settingPickerRow<SelectionValue: Hashable, Content: View>(
        _ label: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Picker("", selection: selection) {
                content()
            }
            .labelsHidden()
            .frame(maxWidth: 230)
        }
    }
}
