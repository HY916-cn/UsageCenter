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
        case .rings: return "双环 + 百分比"
        case .horizontalBar: return "单条 + 百分比"
        case .dualBars: return "双条 + 百分比"
        case .compactBar: return "百分比 + 底条"
        case .statsMini: return "纯数字"
        case .progressOnly: return "仅图标与双环"
        }
    }
}

public enum QuotaPercentMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case remaining
    case used

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .remaining: return "剩余配额"
        case .used: return "已用配额"
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
    case hidden
    case countdown
    case clock

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .hidden: return "窗口简称 (5h / 7d)"
        case .countdown: return "剩余时间 (如 4h / 6d)"
        case .clock: return "重置时刻 (如 04:30)"
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
        case .both: return "5h + 周"
        case .mostConstrained: return "自动最低"
        case .fiveHourOnly: return "仅 5h"
        case .weeklyOnly: return "仅 周"
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
        case .auto: return "自动（最低剩余组）"
        case .gemini: return "Gemini 模型"
        case .thirdParty: return "Claude & GPT"
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
        case .days7: return "7 天"
        case .days30: return "30 天"
        case .days90: return "90 天"
        case .days365: return "1 年"
        case .unlimited: return "永久"
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
        case .quotaDetails: return "配额与余额"
        case .quotaHistory: return "周期趋势图"
        case .tokenActivity: return "Token 活动"
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
    public var customCLIPath: String

    public init(
        provider: ProviderID,
        isEnabled: Bool = true,
        styleOverride: SegmentDisplayStyle? = nil,
        windowVisibility: WindowVisibilityMode = .both,
        showsResetTimeInMenuBar: Bool = true,
        customCLIPath: String = ""
    ) {
        self.provider = provider
        self.isEnabled = isEnabled
        self.styleOverride = styleOverride
        self.windowVisibility = windowVisibility
        self.showsResetTimeInMenuBar = showsResetTimeInMenuBar
        self.customCLIPath = customCLIPath
    }
}

public struct UsageCenterPreferences: Codable, Equatable, Sendable {
    public var sections: [ProviderSectionConfig]
    public var globalStyle: SegmentDisplayStyle
    public var percentMode: QuotaPercentMode
    public var timeDisplayMode: TimeDisplayMode
    public var showsDividers: Bool
    public var monospacedDigits: Bool
    public var antigravityGroup: AntigravityGroupPreference
    public var deepSeekCurrencyPreference: String
    public var deepSeekCustomCommand: String
    public var refreshIntervalSeconds: Int

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
        timeDisplayMode: TimeDisplayMode = .hidden,
        showsDividers: Bool = true,
        monospacedDigits: Bool = true,
        antigravityGroup: AntigravityGroupPreference = .auto,
        deepSeekCurrencyPreference: String = "AUTO",
        deepSeekCustomCommand: String = "",
        refreshIntervalSeconds: Int = 60,
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
        self.showsDividers = showsDividers
        self.monospacedDigits = monospacedDigits
        self.antigravityGroup = antigravityGroup
        self.deepSeekCurrencyPreference = deepSeekCurrencyPreference
        self.deepSeekCustomCommand = deepSeekCustomCommand
        self.refreshIntervalSeconds = refreshIntervalSeconds
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
