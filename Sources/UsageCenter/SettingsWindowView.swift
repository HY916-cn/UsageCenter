import AppKit
import SwiftUI
import UsageCenterCore

/// Native macOS NavigationSplitView + Grouped Form settings window matching CodexMeter.
struct SettingsWindowView: View {
    @ObservedObject var store: UsageCenterStore
    let onOpenHistory: (ProviderID) -> Void

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedSettingsCategory) {
                ForEach(SettingsCategory.allCases) { category in
                    Label(category.title, systemImage: category.symbol)
                        .tag(Optional(category))
                }
            }
            .navigationSplitViewColumnWidth(min: 185, ideal: 205, max: 235)
        } detail: {
            detailPage
                .navigationTitle((store.selectedSettingsCategory ?? .menuAndPopover).title)
        }
        .frame(minWidth: 780, minHeight: 620)
        .applyAppearancePreference(store.preferences.appearance)
        .onAppear {
            store.refreshLaunchAtLoginStatus()
            store.refreshDSHLoginStatus()
            store.reloadHistoryMetadata()
        }
        .alert("确认清空本地历史？", isPresented: $store.showsClearHistoryAlert) {
            Button("取消", role: .cancel) {}
            Button("清空全部历史", role: .destructive) {
                store.clearHistory()
            }
        } message: {
            Text("清空后已记录的配额和余额趋势数据无法恢复。")
        }
    }

    @ViewBuilder
    private var detailPage: some View {
        switch store.selectedSettingsCategory ?? .menuAndPopover {
        case .general:
            generalForm
        case .menuAndPopover:
            menuAndPopoverForm
        case .cliAndAccounts:
            cliAndAccountsForm
        case .notifications:
            notificationsForm
        case .history:
            historyForm
        case .developer:
            developerForm
        case .about:
            aboutForm
        }
    }

    // MARK: - 1. General

    private var generalForm: some View {
        Form {
            Section("外观与启动") {
                Picker("界面外观", selection: $store.preferences.appearance) {
                    ForEach(AppAppearancePreference.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }

                Picker("后台刷新频率", selection: $store.preferences.refreshIntervalSeconds) {
                    Text("每 30 秒").tag(30)
                    Text("每 60 秒（默认，弹窗打开时自动加快至 10 秒）").tag(60)
                    Text("每 2 分钟").tag(120)
                    Text("每 5 分钟").tag(300)
                    Text("仅手动刷新").tag(0)
                }

                Toggle("登录 macOS 时自动启动", isOn: Binding(
                    get: { store.launchAtLoginEnabled },
                    set: { store.setLaunchAtLogin($0) }
                ))
            }

            if let msg = store.statusBannerMessage {
                Section {
                    HStack {
                        Label(msg, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("关闭") { store.statusBannerMessage = nil }
                            .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 2. Menu Bar & Popover (CodexMeter PopoverCustomizationView + Stats Arrangement)

    private var menuAndPopoverForm: some View {
        Form {
            Section {
                Text("自由开关菜单栏中的各个部分、调整左右排列顺序与呈现样式，所有修改即时生效。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("状态栏实时预览") {
                HStack {
                    Spacer()
                    Image(nsImage: StatusSegmentRenderer.renderCompositePreviewImage(
                        preferences: store.preferences,
                        snapshots: store.snapshots
                    ))
                    .interpolation(.high)
                    Spacer()
                }
                .frame(minHeight: 42)
                .background(.bar, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary, lineWidth: 1)
                }
            }

            Section("菜单栏指示器全局样式") {
                Picker("默认呈现形式", selection: $store.preferences.globalStyle) {
                    ForEach(SegmentDisplayStyle.allCases) { style in
                        Text(style.localizedName).tag(style)
                    }
                }

                Picker("配额百分比含义", selection: $store.preferences.percentMode) {
                    ForEach(QuotaPercentMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }

                Picker("下标时间显示", selection: $store.preferences.timeDisplayMode) {
                    ForEach(TimeDisplayMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }

                Picker("官方 SVG 图标模式", selection: $store.preferences.iconColorMode) {
                    ForEach(IconColorMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }

                Toggle("分段间显示分隔竖线", isOn: $store.preferences.showsDividers)
                Toggle("使用等宽数字字体", isOn: $store.preferences.monospacedDigits)
            }

            Section("状态栏显示分段与排列顺序") {
                ForEach(Array(store.preferences.sections.enumerated()), id: \.element.provider) { idx, section in
                    providerOrderAndOptionsRow(
                        section: section,
                        index: idx,
                        total: store.preferences.sections.count
                    )
                }
            }

            Section("点击弹窗显示内容与顺序") {
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
            }

            Section {
                Button("恢复默认布局与样式") {
                    store.restoreDefaultPreferences()
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func providerOrderAndOptionsRow(section: ProviderSectionConfig, index: Int, total: Int) -> some View {
        let provider = section.provider
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                BrandBadgeView(provider: provider, size: 16, iconMode: .brand)
                Toggle(
                    provider.displayName,
                    isOn: Binding(
                        get: { section.isEnabled },
                        set: { val in store.preferences.updateSection(provider) { $0.isEnabled = val } }
                    )
                )

                Spacer()

                Button {
                    store.preferences.moveSection(provider, by: -1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .help("上移 \(provider.displayName)")

                Button {
                    store.preferences.moveSection(provider, by: 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(index >= total - 1)
                .help("下移 \(provider.displayName)")
            }

            if section.isEnabled {
                HStack(spacing: 14) {
                    Picker("样式", selection: Binding<SegmentDisplayStyle?>(
                        get: { section.styleOverride },
                        set: { val in store.preferences.updateSection(provider) { $0.styleOverride = val } }
                    )) {
                        Text("跟随全局").tag(SegmentDisplayStyle?.none)
                        ForEach(SegmentDisplayStyle.allCases) { style in
                            Text(style.localizedName).tag(Optional(style))
                        }
                    }
                    .controlSize(.small)

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

                        Toggle("显示时间", isOn: Binding(
                            get: { section.showsResetTimeInMenuBar },
                            set: { val in store.preferences.updateSection(provider) { $0.showsResetTimeInMenuBar = val } }
                        ))
                        .controlSize(.small)
                    } else {
                        Picker("币种", selection: $store.preferences.deepSeekCurrencyPreference) {
                            Text("自动").tag("AUTO")
                            Text("CNY (¥)").tag("CNY")
                            Text("USD ($)").tag("USD")
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.leading, 26)

                if provider == .antigravity {
                    Picker("状态栏模型组", selection: $store.preferences.antigravityGroup) {
                        ForEach(AntigravityGroupPreference.allCases) { g in
                            Text(g.localizedName).tag(g)
                        }
                    }
                    .controlSize(.small)
                    .padding(.leading, 26)
                }
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - 3. CLI & Accounts (Including Local DSH Login Auto-Detection)

    private var cliAndAccountsForm: some View {
        Form {
            Section("DeepSeek 本地 DSH 登录账户（优先读取）") {
                LabeledContent("DSH 凭证文件") {
                    if store.hasDSHLocalLogin {
                        Label("已登录（~/.dsh/.credentials.yaml）", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("未检测到 DSH 登录记录", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if let bal = store.snapshot(for: .deepseek).preferredBalance(currencyPreference: store.preferences.deepSeekCurrencyPreference) {
                    LabeledContent("当前读取余额") {
                        Text("\(bal.formattedTotal)（充值 \(bal.formattedToppedUp) / 赠送 \(bal.formattedGranted)）")
                            .monospacedDigit()
                    }
                }

                HStack {
                    Button("重新检测并刷新 DSH 余额") {
                        Task { await store.refresh(provider: .deepseek) }
                    }
                    Spacer()
                }
            }

            Section("本地 CLI 路径与状态检测") {
                ForEach([ProviderID.claude, .chatgpt, .antigravity]) { provider in
                    let detected = store.detectedCLIPath(for: provider)
                    let cfg = store.preferences.config(for: provider)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            BrandBadgeView(provider: provider, size: 15, iconMode: .brand)
                            Text(provider.displayName)
                                .fontWeight(.medium)
                            Spacer()
                            if let detected {
                                Label(detected, systemImage: "checkmark.circle.fill")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.green)
                            } else {
                                Label("未找到 \(provider.defaultBinaryName)", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            Button("刷新") {
                                Task { await store.refresh(provider: provider) }
                            }
                            .controlSize(.small)
                        }

                        TextField(
                            "可选自定义 \(provider.defaultBinaryName) 可执行文件路径",
                            text: Binding(
                                get: { cfg.customCLIPath },
                                set: { val in store.preferences.updateSection(provider) { $0.customCLIPath = val } }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                    }
                    .padding(.vertical, 3)
                }
            }

            Section("DeepSeek 备用选项（仅在未使用 DSH 登录时生效）") {
                HStack {
                    SecureField("可选备用 DeepSeek API Key (sk-...)", text: $store.deepSeekAPIKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Button("保存至钥匙串") {
                        store.saveDeepSeekKey()
                    }
                    .disabled(store.deepSeekAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if store.hasStoredDeepSeekKey {
                        Button("清除", role: .destructive) {
                            store.clearDeepSeekKey()
                        }
                    }
                }

                TextField("可选自定义 CLI 命令（留空默认读取 DSH 登录账号）", text: $store.preferences.deepSeekCustomCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 4. Notifications

    private var notificationsForm: some View {
        Form {
            Section("本地配额通知") {
                Toggle("启用 macOS 本地配额提醒", isOn: Binding(
                    get: { store.preferences.notificationsEnabled },
                    set: { store.setNotificationsEnabled($0) }
                ))

                Stepper(
                    "低配额告警阈值：剩余低于 \(store.preferences.lowQuotaThreshold)%",
                    value: $store.preferences.lowQuotaThreshold,
                    in: 5...50,
                    step: 5
                )

                Toggle("消耗速度超出剩余时间比例时提醒", isOn: $store.preferences.notifyOnOverPace)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 5. History & Storage

    private var historyForm: some View {
        Form {
            Section("本地历史记录存储") {
                Picker("历史保留时长", selection: $store.preferences.historyRetention) {
                    ForEach(HistoryRetentionPolicy.allCases) { p in
                        Text(p.localizedName).tag(p)
                    }
                }

                LabeledContent("当前占用空间") {
                    Text(ByteCountFormatter.string(fromByteCount: store.historyStorageBytes, countStyle: .file))
                        .foregroundStyle(.secondary)
                }

                LabeledContent("已保存采样数") {
                    Text("\(store.historySamples.count) 条")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button("打开完整用量历史窗口…") {
                        onOpenHistory(store.activeProvider)
                    }

                    Button("导出 CSV…") {
                        store.exportHistoryCSVInteractive()
                    }
                    .disabled(store.historySamples.isEmpty)

                    Button("清空历史记录…", role: .destructive) {
                        store.showsClearHistoryAlert = true
                    }
                    .disabled(store.historySamples.isEmpty)
                }

                Text("历史数据仅保存在本机 ~/Library/Application Support/UsageCenter，不包含任何登录令牌或邮箱信息。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 6. Developer Preview

    private var developerForm: some View {
        Form {
            Section("菜单栏状态模拟预览") {
                Toggle("在菜单栏启用模拟预览数值", isOn: $store.preferences.developerPreviewEnabled)

                LabeledContent("模拟剩余配额：\(Int(store.preferences.developerPreviewRemaining.rounded()))%") {
                    Slider(value: $store.preferences.developerPreviewRemaining, in: 0...100, step: 1)
                        .frame(maxWidth: 260)
                }

                LabeledContent("模拟剩余时间：\(Int(store.preferences.developerPreviewTimeRemaining.rounded()))%") {
                    Slider(value: $store.preferences.developerPreviewTimeRemaining, in: 0...100, step: 1)
                        .frame(maxWidth: 260)
                }
            }

            Section("历史图表演示数据") {
                HStack(spacing: 12) {
                    Button("生成 7 天模拟历史曲线") {
                        store.generateDemoHistory()
                    }
                    Button("清空历史数据", role: .destructive) {
                        store.clearHistory()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 7. About

    private var aboutForm: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        BrandBadgeView(provider: .claude, size: 22)
                        BrandBadgeView(provider: .chatgpt, size: 22)
                        BrandBadgeView(provider: .antigravity, size: 22)
                        BrandBadgeView(provider: .deepseek, size: 22)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("UsageCenter")
                            .font(.title2.weight(.semibold))
                        Text("版本 1.1.0 (Build 2)")
                            .foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://github.com/HY916-cn/UsageCenter")!) {
                            Label("GitHub 仓库", systemImage: "link")
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("数据来源与隐私") {
                Text("UsageCenter 仅在本地与已安装的 Claude CLI、Codex App Server、Antigravity CLI 以及本地已登录的 DSH 账户通信，不会上传任何统计或遥测信息。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
