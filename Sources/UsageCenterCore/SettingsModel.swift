import Foundation

public enum SegmentDisplayStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case stack
    case rings
    case bars
    case compact
    case minimal

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .stack: return "双行堆叠（5h + 周 + 时间）"
        case .rings: return "同心双环 + 数值"
        case .bars: return "双进度条 + 数值"
        case .compact: return "单行紧凑数值"
        case .minimal: return "极简图标与图形"
        }
    }
}

public enum QuotaPercentMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case used
    case remaining

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .used: return "显示已用比例 (Used%)"
        case .remaining: return "显示剩余比例 (Remaining%)"
        }
    }

    public var shortVerb: String {
        switch self {
        case .used: return "已用"
        case .remaining: return "剩余"
        }
    }
}

public enum TimeDisplayMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case countdown
    case clock
    case hidden

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .countdown: return "重置倒计时 (如 4h20m)"
        case .clock: return "重置时间点 (如 04:30)"
        case .hidden: return "菜单栏不显示时间（仅详情显示）"
        }
    }
}

public enum WindowVisibilityMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case both
    case fiveHourOnly
    case weeklyOnly
    case mostConstrained

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .both: return "同时显示 5h 与周用量"
        case .fiveHourOnly: return "仅显示 5h 用量"
        case .weeklyOnly: return "仅显示周用量"
        case .mostConstrained: return "自动显示最紧张窗口"
        }
    }
}

public enum AntigravityGroupPreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case auto
    case gemini
    case thirdParty

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .auto: return "自动（剩余最少模型组）"
        case .gemini: return "Gemini 模型组"
        case .thirdParty: return "Claude & GPT 模型组"
        }
    }
}

public enum IconColorMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case brand
    case monochrome

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .brand: return "彩色品牌图标"
        case .monochrome: return "单色系统自适应图标"
        }
    }
}

public enum AppAppearancePreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色模式"
        case .dark: return "深色模式"
        }
    }
}

public struct ProviderSectionConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: ProviderID { provider }
    public var provider: ProviderID
    public var isEnabled: Bool
    public var styleOverride: SegmentDisplayStyle?
    public var windowVisibility: WindowVisibilityMode
    public var showsResetTimeInMenuBar: Bool
    public var showsProviderLabel: Bool
    public var customCLIPath: String

    public init(
        provider: ProviderID,
        isEnabled: Bool = true,
        styleOverride: SegmentDisplayStyle? = nil,
        windowVisibility: WindowVisibilityMode = .both,
        showsResetTimeInMenuBar: Bool = true,
        showsProviderLabel: Bool = false,
        customCLIPath: String = ""
    ) {
        self.provider = provider
        self.isEnabled = isEnabled
        self.styleOverride = styleOverride
        self.windowVisibility = windowVisibility
        self.showsResetTimeInMenuBar = showsResetTimeInMenuBar
        self.showsProviderLabel = showsProviderLabel
        self.customCLIPath = customCLIPath
    }
}

public struct UsageCenterPreferences: Codable, Equatable, Sendable {
    public var sections: [ProviderSectionConfig]
    public var globalStyle: SegmentDisplayStyle
    public var percentMode: QuotaPercentMode
    public var timeDisplayMode: TimeDisplayMode
    public var iconColorMode: IconColorMode
    public var showsDividers: Bool
    public var monospacedDigits: Bool
    public var antigravityGroup: AntigravityGroupPreference
    public var deepSeekCurrencyPreference: String
    public var deepSeekCustomCommand: String
    public var refreshIntervalSeconds: Int
    public var appearance: AppAppearancePreference

    public init(
        sections: [ProviderSectionConfig] = ProviderID.allCases.map { ProviderSectionConfig(provider: $0) },
        globalStyle: SegmentDisplayStyle = .stack,
        percentMode: QuotaPercentMode = .used,
        timeDisplayMode: TimeDisplayMode = .countdown,
        iconColorMode: IconColorMode = .brand,
        showsDividers: Bool = true,
        monospacedDigits: Bool = true,
        antigravityGroup: AntigravityGroupPreference = .auto,
        deepSeekCurrencyPreference: String = "AUTO",
        deepSeekCustomCommand: String = "",
        refreshIntervalSeconds: Int = 60,
        appearance: AppAppearancePreference = .system
    ) {
        self.sections = Self.normalizedSections(sections)
        self.globalStyle = globalStyle
        self.percentMode = percentMode
        self.timeDisplayMode = timeDisplayMode
        self.iconColorMode = iconColorMode
        self.showsDividers = showsDividers
        self.monospacedDigits = monospacedDigits
        self.antigravityGroup = antigravityGroup
        self.deepSeekCurrencyPreference = deepSeekCurrencyPreference
        self.deepSeekCustomCommand = deepSeekCustomCommand
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.appearance = appearance
    }

    public var enabledSections: [ProviderSectionConfig] {
        sections.filter(\.isEnabled)
    }

    public func config(for provider: ProviderID) -> ProviderSectionConfig {
        sections.first { $0.provider == provider } ?? ProviderSectionConfig(provider: provider)
    }

    public func effectiveStyle(for provider: ProviderID) -> SegmentDisplayStyle {
        config(for: provider).styleOverride ?? globalStyle
    }

    public mutating func updateSection(_ provider: ProviderID, _ transform: (inout ProviderSectionConfig) -> Void) {
        guard let index = sections.firstIndex(where: { $0.provider == provider }) else { return }
        transform(&sections[index])
    }

    public mutating func moveSection(_ provider: ProviderID, by offset: Int) {
        guard let index = sections.firstIndex(where: { $0.provider == provider }) else { return }
        let target = min(max(0, index + offset), sections.count - 1)
        guard target != index else { return }
        let item = sections.remove(at: index)
        sections.insert(item, at: target)
    }

    public static func normalizedSections(_ input: [ProviderSectionConfig]) -> [ProviderSectionConfig] {
        var result: [ProviderSectionConfig] = []
        var seen = Set<ProviderID>()
        for config in input where seen.insert(config.provider).inserted {
            result.append(config)
        }
        for provider in ProviderID.allCases where !seen.contains(provider) {
            result.append(ProviderSectionConfig(provider: provider))
        }
        return result
    }
}
