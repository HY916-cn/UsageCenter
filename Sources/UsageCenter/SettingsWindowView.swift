import AppKit
import SwiftUI
import UsageCenterCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case layout
    case cli
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .layout: return "组件与呈现"
        case .cli: return "CLI 与凭据"
        case .general: return "通用与关于"
        }
    }

    var symbol: String {
        switch self {
        case .layout: return "menubar.rectangle"
        case .cli: return "terminal"
        case .general: return "gearshape"
        }
    }
}

struct SettingsWindowView: View {
    @ObservedObject var store: UsageCenterStore

    var body: some View {
        ZStack {
            LiquidBackdrop(accent: Color(red: 0.29, green: 0.56, blue: 0.99))
            mainContainer
        }
        .frame(minWidth: 740, idealWidth: 820, minHeight: 620, idealHeight: 720)
        .background(ModernWindowChromeConfigurator(title: "UsageCenter 设置"))
        .applyAppearancePreference(store.preferences.appearance)
    }

    @ViewBuilder
    private var mainContainer: some View {
        if #available(macOS 26.0, *) {
            scrollBody
                .safeAreaBar(edge: .top, spacing: 0) {
                    topChromeHeader
                }
        } else {
            scrollBody
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        topChromeHeader
                        Divider().opacity(0.35)
                    }
                    .background(.ultraThinMaterial)
                }
        }
    }

    private var topChromeHeader: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("UsageCenter")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("单组件统一监控 Claude · ChatGPT · Antigravity · DeepSeek")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(SettingsTab.allCases) { tab in
                        let active = (store.selectedSettingsTab == tab)
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                store.selectedSettingsTab = tab
                            }
                        } label: {
                            Label(tab.title, systemImage: tab.symbol)
                                .font(.caption.weight(active ? .semibold : .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background {
                                    if active {
                                        Capsule().fill(Color.accentColor.opacity(0.20))
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(active ? .primary : .secondary)
                    }
                }
                .padding(4)
                .liquidGlassCapsule()
            }

            liveMenuBarPreviewStrip
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var liveMenuBarPreviewStrip: some View {
        HStack(spacing: 12) {
            Label("状态栏实时预览", systemImage: "sparkles.rectangle.stack")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Image(nsImage: StatusSegmentRenderer.renderCompositePreviewImage(
                preferences: store.preferences,
                snapshots: store.snapshots
            ))
            .interpolation(.high)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .liquidGlassCard(cornerRadius: 14)
    }

    private var scrollBody: some View {
        ScrollView {
            LiquidGlassStage(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    if let banner = store.statusBannerMessage {
                        HStack {
                            Label(banner, systemImage: "info.circle.fill")
                                .font(.caption)
                            Spacer()
                            Button("知道了") {
                                store.statusBannerMessage = nil
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                        }
                        .padding(12)
                        .liquidGlassCard(cornerRadius: 14)
                    }

                    switch store.selectedSettingsTab {
                    case .layout:
                        layoutSettingsContent
                    case .cli:
                        cliSettingsContent
                    case .general:
                        generalSettingsContent
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 26)
            }
        }
    }

    // MARK: - Tab 1: Layout & Presentation

    @ViewBuilder
    private var layoutSettingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("全局呈现样式", subtitle: "控制菜单栏统一组件的默认视觉风格、时间格式与图标色彩")

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Text("默认呈现形式")
                        .font(.subheadline.weight(.medium))
                    Picker("", selection: $store.preferences.globalStyle) {
                        ForEach(SegmentDisplayStyle.allCases) { style in
                            Text(style.localizedName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }

                GridRow {
                    Text("配额数值模式")
                        .font(.subheadline.weight(.medium))
                    Picker("", selection: $store.preferences.percentMode) {
                        ForEach(QuotaPercentMode.allCases) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }

                GridRow {
                    Text("对应时间显示")
                        .font(.subheadline.weight(.medium))
                    Picker("", selection: $store.preferences.timeDisplayMode) {
                        ForEach(TimeDisplayMode.allCases) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }

                GridRow {
                    Text("品牌图标风格")
                        .font(.subheadline.weight(.medium))
                    Picker("", selection: $store.preferences.iconColorMode) {
                        ForEach(IconColorMode.allCases) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }
            }

            Divider().opacity(0.35)

            HStack(spacing: 24) {
                Toggle("显示分段间分隔竖线", isOn: $store.preferences.showsDividers)
                Toggle("使用等宽数字字体（防止跳动）", isOn: $store.preferences.monospacedDigits)
            }
            .font(.subheadline)
        }
        .padding(18)
        .liquidGlassCard(cornerRadius: 20)

        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("各服务显示开关、排列顺序与独立样式", subtitle: "点击菜单栏对应分段即可弹出对应服务的详情卡片")

            ForEach(Array(store.preferences.sections.enumerated()), id: \.element.provider) { idx, section in
                providerSectionCard(section: section, index: idx, total: store.preferences.sections.count)
            }
        }
        .padding(18)
        .liquidGlassCard(cornerRadius: 20)
    }

    private func providerSectionCard(section: ProviderSectionConfig, index: Int, total: Int) -> some View {
        let provider = section.provider
        let accent = BrandIconRenderer.swiftUIAccent(for: provider)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BrandBadgeView(provider: provider, size: 18, iconMode: .brand)

                Text(provider.displayName)
                    .font(.headline)

                Text(provider.isQuotaProvider ? "5h + 周用量" : "API 余额")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.14), in: Capsule())

                Spacer()

                Button {
                    store.preferences.moveSection(provider, by: -1)
                } label: {
                    Image(systemName: "arrow.up")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .help("向前移动")

                Button {
                    store.preferences.moveSection(provider, by: 1)
                } label: {
                    Image(systemName: "arrow.down")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(index >= total - 1)
                .help("向后移动")

                Toggle("显示", isOn: Binding(
                    get: { section.isEnabled },
                    set: { val in store.preferences.updateSection(provider) { $0.isEnabled = val } }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if section.isEnabled {
                Divider().opacity(0.25)

                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Text("呈现形式")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: Binding<SegmentDisplayStyle?>(
                            get: { section.styleOverride },
                            set: { val in store.preferences.updateSection(provider) { $0.styleOverride = val } }
                        )) {
                            Text("跟随全局").tag(SegmentDisplayStyle?.none)
                            ForEach(SegmentDisplayStyle.allCases) { s in
                                Text(s.localizedName).tag(Optional(s))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 175)
                    }

                    if provider.isQuotaProvider {
                        HStack(spacing: 6) {
                            Text("窗口")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { section.windowVisibility },
                                set: { val in store.preferences.updateSection(provider) { $0.windowVisibility = val } }
                            )) {
                                ForEach(WindowVisibilityMode.allCases) { m in
                                    Text(m.localizedName).tag(m)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 165)
                        }

                        Toggle("显示时间", isOn: Binding(
                            get: { section.showsResetTimeInMenuBar },
                            set: { val in store.preferences.updateSection(provider) { $0.showsResetTimeInMenuBar = val } }
                        ))
                        .font(.caption)
                    } else {
                        HStack(spacing: 6) {
                            Text("优先币种")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: $store.preferences.deepSeekCurrencyPreference) {
                                Text("自动识别").tag("AUTO")
                                Text("人民币 (¥ CNY)").tag("CNY")
                                Text("美元 ($ USD)").tag("USD")
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                    }

                    Toggle("前缀简称", isOn: Binding(
                        get: { section.showsProviderLabel },
                        set: { val in store.preferences.updateSection(provider) { $0.showsProviderLabel = val } }
                    ))
                    .font(.caption)
                }

                if provider == .antigravity {
                    HStack(spacing: 8) {
                        Text("Antigravity 状态栏默认模型组：")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $store.preferences.antigravityGroup) {
                            ForEach(AntigravityGroupPreference.allCases) { pref in
                                Text(pref.localizedName).tag(pref)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        Text("（点击 Antigravity 分段可在弹窗查看全部模型组）")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(13)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Tab 2: CLI & Credentials

    @ViewBuilder
    private var cliSettingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("本地 CLI 可执行文件检测与自定义路径", subtitle: "所有数据均通过本机已安装的 CLI 与系统工具直接读取")

            ForEach(ProviderID.allCases) { provider in
                cliProviderRow(provider)
            }
        }
        .padding(18)
        .liquidGlassCard(cornerRadius: 20)

        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("DeepSeek API 余额 CLI 配置", subtitle: "支持系统钥匙串 + 本地 curl 安全查询，或使用自定义本地 CLI 脚本")

            HStack(spacing: 10) {
                SecureField("输入 DeepSeek API Key (sk-...)", text: $store.deepSeekAPIKeyInput)
                    .textFieldStyle(.roundedBorder)

                Button("保存至钥匙串") {
                    store.saveDeepSeekKey()
                }
                .disabled(store.deepSeekAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if store.hasStoredDeepSeekKey {
                    Button("清除密钥", role: .destructive) {
                        store.clearDeepSeekKey()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("可选：自定义本地 DeepSeek CLI 命令（留空则默认调用 /usr/bin/curl 查询官方余额接口）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("例如：deepseek balance --json", text: $store.preferences.deepSeekCustomCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
            }
        }
        .padding(18)
        .liquidGlassCard(cornerRadius: 20)
    }

    private func cliProviderRow(_ provider: ProviderID) -> some View {
        let detected = store.detectedCLIPath(for: provider)
        let config = store.preferences.config(for: provider)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                BrandBadgeView(provider: provider, size: 16, iconMode: .brand)
                Text(provider.displayName)
                    .font(.subheadline.weight(.semibold))
                Text("(\(provider.cliMethodSummary))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)

                Spacer()

                if let detected {
                    Label(detected, systemImage: "checkmark.circle.fill")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.green)
                } else {
                    Label("未找到 \(provider.defaultBinaryName)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Button("测试刷新") {
                    Task { await store.refresh(provider: provider) }
                }
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                Text("自定义路径：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "留空自动搜索 ~/.local/bin, /opt/homebrew/bin, /usr/local/bin 等",
                    text: Binding(
                        get: { config.customCLIPath },
                        set: { val in store.preferences.updateSection(provider) { $0.customCLIPath = val } }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
            }
        }
        .padding(12)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Tab 3: General & About

    @ViewBuilder
    private var generalSettingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("通用偏好设置", subtitle: "管理后台刷新频率、界面外观与登录启动项")

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Text("后台自动刷新间隔")
                        .font(.subheadline.weight(.medium))
                    Picker("", selection: $store.preferences.refreshIntervalSeconds) {
                        Text("每 30 秒").tag(30)
                        Text("每 1 分钟（推荐）").tag(60)
                        Text("每 2 分钟").tag(120)
                        Text("每 5 分钟").tag(300)
                        Text("仅手动刷新").tag(0)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }

                GridRow {
                    Text("界面外观主题")
                        .font(.subheadline.weight(.medium))
                    Picker("", selection: $store.preferences.appearance) {
                        ForEach(AppAppearancePreference.allCases) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }
            }

            Divider().opacity(0.35)

            HStack {
                Toggle("登录 macOS 时自动启动 UsageCenter", isOn: Binding(
                    get: { store.launchAtLoginEnabled },
                    set: { store.setLaunchAtLogin($0) }
                ))

                Spacer()

                Button("恢复默认显示布局") {
                    store.restoreDefaultPreferences()
                }
            }
        }
        .padding(18)
        .liquidGlassCard(cornerRadius: 20)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 52, height: 52)
                    HStack(spacing: 3) {
                        BrandBadgeView(provider: .claude, size: 18)
                        BrandBadgeView(provider: .chatgpt, size: 18)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("UsageCenter 1.0.0")
                        .font(.title3.weight(.bold))
                    Text("基于本地 CLI 的多模型配额与余额状态栏中心 · 原生 Liquid Glass 界面")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("GitHub 仓库：https://github.com/HY916-cn/UsageCenter",
                         destination: URL(string: "https://github.com/HY916-cn/UsageCenter")!)
                        .font(.caption)
                }
            }
        }
        .padding(18)
        .liquidGlassCard(cornerRadius: 20)
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.bold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
