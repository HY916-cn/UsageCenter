import Foundation

public enum SegmentDisplayStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case rings
    case horizontalBar
    case dualBars
    case compactBar
    case statsMini
    case progressOnly

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .rings: return "同心双环 + 百分比（CodexMeter 默认）"
        case .horizontalBar: return "横向进度条 + 百分比"
        case .dualBars: return "双进度条（配额+时间）+ 百分比"
        case .compactBar: return "百分比 + 底部紧凑条"
        case .statsMini: return "双层纯文字（Stats Mini 风格）"
        case .progressOnly: return "仅图标与同心双环"
        }
    }
}

public enum QuotaPercentMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case remaining
    case used

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .remaining: return "剩余配额 (Remaining%)"
        case .used: return "已用配额 (Used%)"
        }
    }

    public var shortVerb: String {
        switch self {
        case .remaining: return "剩余"
        case .used: return "已用"
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
        case .countdown: return "窗口 + 剩余时间 (如 5h·4h)"
        case .clock: return "窗口 + 重置时间 (如 5h·04:30)"
        case .hidden: return "仅显示窗口名 (5h / 周)"
        }
    }
}

public enum WindowVisibilityMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case both
    case mostConstrained
    case fiveHourOnly
    case weeklyOnly

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .both: return "同时显示 5小时 与 周配额"
        case .mostConstrained: return "自动（显示剩余最少窗口）"
        case .fiveHourOnly: return "仅 5小时配额"
        case .weeklyOnly: return "仅 周配额"
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
        case .brand: return "彩色官方 SVG 图标"
        case .monochrome: return "单色自适应状态栏图标"
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
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

public enum HistoryRetentionPolicy: Int, CaseIterable, Codable, Identifiable, Sendable {
    case days7 = 7
    case days30 = 30
    case days90 = 90
    case days365 = 365
    case unlimited = 0

    public var id: Int { rawValue }

    public var localizedName: String {
        switch self {
        case .days7: return "保留 7 天"
        case .days30: return "保留 30 天"
        case .days90: return "保留 90 天"
        case .days365: return "保留 1 年"
        case .unlimited: return "永久保留"
        }
    }
}

public enum PopoverSectionKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case quotaDetails
    case quotaHistory
    case tokenActivity

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .quotaDetails: return "配额与余额详情"
        case .quotaHistory: return "周期历史趋势图"
        case .tokenActivity: return "近 30 天 Token 活动"
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

    // Popover & History & Notifications (CodexMeter parity)
    public var popoverSections: [PopoverSectionKind]
    public var hiddenPopoverSections: Set<PopoverSectionKind>
    public var historyRetention: HistoryRetentionPolicy
    public var notificationsEnabled: Bool
    public var lowQuotaThreshold: Int
    public var notifyOnOverPace: Bool
    public var developerPreviewEnabled: Bool
    public var developerPreviewRemaining: Double
    public var developerPreviewTimeRemaining: Double

    public init(
        sections: [ProviderSectionConfig] = ProviderID.allCases.map { ProviderSectionConfig(provider: $0) },
        globalStyle: SegmentDisplayStyle = .rings,
        percentMode: QuotaPercentMode = .remaining,
        timeDisplayMode: TimeDisplayMode = .countdown,
        iconColorMode: IconColorMode = .brand,
        showsDividers: Bool = true,
        monospacedDigits: Bool = true,
        antigravityGroup: AntigravityGroupPreference = .auto,
        deepSeekCurrencyPreference: String = "AUTO",
        deepSeekCustomCommand: String = "",
        refreshIntervalSeconds: Int = 60,
        appearance: AppAppearancePreference = .system,
        popoverSections: [PopoverSectionKind] = PopoverSectionKind.allCases,
        hiddenPopoverSections: Set<PopoverSectionKind> = [],
        historyRetention: HistoryRetentionPolicy = .days90,
        notificationsEnabled: Bool = false,
        lowQuotaThreshold: Int = 20,
        notifyOnOverPace: Bool = true,
        developerPreviewEnabled: Bool = false,
        developerPreviewRemaining: Double = 72,
        developerPreviewTimeRemaining: Double = 55
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
        self.popoverSections = Self.normalizedPopoverSections(popoverSections)
        self.hiddenPopoverSections = hiddenPopoverSections
        self.historyRetention = historyRetention
        self.notificationsEnabled = notificationsEnabled
        self.lowQuotaThreshold = min(50, max(5, lowQuotaThreshold))
        self.notifyOnOverPace = notifyOnOverPace
        self.developerPreviewEnabled = developerPreviewEnabled
        self.developerPreviewRemaining = developerPreviewRemaining
        self.developerPreviewTimeRemaining = developerPreviewTimeRemaining
    }

    public var enabledSections: [ProviderSectionConfig] {
        sections.filter(\.isEnabled)
    }

    public var visiblePopoverSections: [PopoverSectionKind] {
        popoverSections.filter { !hiddenPopoverSections.contains($0) }
    }

    public func isPopoverSectionVisible(_ section: PopoverSectionKind) -> Bool {
        !hiddenPopoverSections.contains(section)
    }

    public mutating func setPopoverSection(_ section: PopoverSectionKind, visible: Bool) {
        if visible {
            hiddenPopoverSections.remove(section)
        } else {
            hiddenPopoverSections.insert(section)
        }
    }

    public mutating func movePopoverSection(_ section: PopoverSectionKind, by offset: Int) {
        guard let idx = popoverSections.firstIndex(of: section) else { return }
        let dst = min(max(0, idx + offset), popoverSections.count - 1)
        guard dst != idx else { return }
        let item = popoverSections.remove(at: idx)
        popoverSections.insert(item, at: dst)
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

    public static func normalizedPopoverSections(_ input: [PopoverSectionKind]) -> [PopoverSectionKind] {
        var result: [PopoverSectionKind] = []
        var seen = Set<PopoverSectionKind>()
        for s in input where seen.insert(s).inserted {
            result.append(s)
        }
        for s in PopoverSectionKind.allCases where !seen.contains(s) {
            result.append(s)
        }
        return result
    }
}
