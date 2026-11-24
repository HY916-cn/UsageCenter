import Foundation

public enum ProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude
    case chatgpt
    case antigravity
    case deepseek

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .antigravity: return "Antigravity"
        case .deepseek: return "DeepSeek"
        }
    }

    public var shortLabel: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "GPT"
        case .antigravity: return "AGY"
        case .deepseek: return "DS"
        }
    }

    public var defaultBinaryName: String {
        switch self {
        case .claude: return "claude"
        case .chatgpt: return "codex"
        case .antigravity: return "agy"
        case .deepseek: return "curl"
        }
    }

    public var cliMethodSummary: String {
        switch self {
        case .claude: return "claude -p \"/usage\" --output-format json"
        case .chatgpt: return "codex app-server --listen stdio://"
        case .antigravity: return "agy -p \"/usage\" --output-format json"
        case .deepseek: return "curl https://api.deepseek.com/user/balance"
        }
    }

    public var isQuotaProvider: Bool {
        self != .deepseek
    }
}

public enum WindowKind: String, Codable, Equatable, Sendable {
    case fiveHour
    case weekly
    case other
}

public enum ConsumptionPace: Equatable, Sendable {
    case onTrack
    case overPace
    case unavailable
}

public enum QuotaAttentionLevel: Equatable, Sendable {
    case normal
    case warning
    case critical
}

public struct QuotaWindow: Identifiable, Equatable, Sendable {
    public let id: String
    public let groupID: String?
    public let groupName: String?
    public let title: String
    public let kind: WindowKind
    public let usedPercent: Int
    public let durationMinutes: Int?
    public let resetsAt: Date?
    public let resetRawText: String?
    public let detailText: String?

    public init(
        id: String,
        groupID: String? = nil,
        groupName: String? = nil,
        title: String,
        kind: WindowKind,
        usedPercent: Int,
        durationMinutes: Int?,
        resetsAt: Date?,
        resetRawText: String? = nil,
        detailText: String? = nil
    ) {
        self.id = id
        self.groupID = groupID
        self.groupName = groupName
        self.title = title
        self.kind = kind
        self.usedPercent = min(100, max(0, usedPercent))
        self.durationMinutes = durationMinutes
        self.resetsAt = resetsAt
        self.resetRawText = resetRawText
        self.detailText = detailText
    }

    public var remainingPercent: Int {
        min(100, max(0, 100 - usedPercent))
    }

    public func displayPercent(mode: QuotaPercentMode) -> Int {
        switch mode {
        case .used: return usedPercent
        case .remaining: return remainingPercent
        }
    }

    public func remainingTimePercent(at now: Date) -> Double? {
        guard let durationMinutes, durationMinutes > 0, let resetsAt else {
            return nil
        }
        let remainingSeconds = resetsAt.timeIntervalSince(now)
        guard remainingSeconds >= 0 else { return 0 }
        let totalSeconds = Double(durationMinutes) * 60.0
        return min(100, max(0, remainingSeconds / totalSeconds * 100.0))
    }

    public func elapsedTimePercent(at now: Date) -> Double? {
        guard let rem = remainingTimePercent(at: now) else { return nil }
        return min(100, max(0, 100.0 - rem))
    }

    public func pace(at now: Date) -> ConsumptionPace {
        guard let remainingTime = remainingTimePercent(at: now) else {
            return .unavailable
        }
        return Double(remainingPercent) >= remainingTime ? .onTrack : .overPace
    }

    public func attentionLevel(at now: Date, lowRemainingThreshold: Int = 20) -> QuotaAttentionLevel {
        if remainingPercent <= lowRemainingThreshold {
            return .critical
        }
        return pace(at: now) == .overPace ? .warning : .normal
    }

    public func shortTimeLabel(at now: Date, mode: TimeDisplayMode) -> String? {
        switch mode {
        case .hidden:
            return nil
        case .countdown:
            if let resetsAt {
                return TimeFormatting.compactCountdown(until: resetsAt, from: now)
            }
            return nil
        case .clock:
            if let resetsAt {
                return TimeFormatting.compactResetClock(resetsAt, kind: kind, now: now)
            }
            return resetRawText
        }
    }
}

public struct DeepSeekBalanceItem: Identifiable, Equatable, Sendable {
    public var id: String { currency }
    public let currency: String
    public let totalBalance: String
    public let grantedBalance: String
    public let toppedUpBalance: String

    public init(
        currency: String,
        totalBalance: String,
        grantedBalance: String = "0.00",
        toppedUpBalance: String = "0.00"
    ) {
        self.currency = currency.uppercased()
        self.totalBalance = totalBalance
        self.grantedBalance = grantedBalance
        self.toppedUpBalance = toppedUpBalance
    }

    public var currencySymbol: String {
        switch currency {
        case "CNY", "RMB": return "¥"
        case "USD": return "$"
        case "EUR": return "€"
        default: return currency + " "
        }
    }

    public var formattedTotal: String {
        "\(currencySymbol)\(totalBalance)"
    }

    public var numericTotal: Double {
        Double(totalBalance) ?? 0
    }
}

public struct ProviderSnapshot: Equatable, Sendable {
    public let provider: ProviderID
    public var accountLabel: String?
    public var windows: [QuotaWindow]
    public var balances: [DeepSeekBalanceItem]
    public var isAvailable: Bool?
    public var updatedAt: Date?
    public var isLoading: Bool
    public var isStale: Bool
    public var errorMessage: String?

    public init(
        provider: ProviderID,
        accountLabel: String? = nil,
        windows: [QuotaWindow] = [],
        balances: [DeepSeekBalanceItem] = [],
        isAvailable: Bool? = nil,
        updatedAt: Date? = nil,
        isLoading: Bool = false,
        isStale: Bool = false,
        errorMessage: String? = nil
    ) {
        self.provider = provider
        self.accountLabel = accountLabel
        self.windows = windows
        self.balances = balances
        self.isAvailable = isAvailable
        self.updatedAt = updatedAt
        self.isLoading = isLoading
        self.isStale = isStale
        self.errorMessage = errorMessage
    }

    public var hasData: Bool {
        !windows.isEmpty || !balances.isEmpty
    }

    public func resolvedWindows(antigravityGroup: AntigravityGroupPreference) -> (fiveHour: QuotaWindow?, weekly: QuotaWindow?) {
        let candidateWindows: [QuotaWindow]
        if provider == .antigravity {
            candidateWindows = filterAntigravityWindows(preference: antigravityGroup)
        } else {
            candidateWindows = windows
        }
        let fiveHour = candidateWindows.first { $0.kind == .fiveHour }
        let weekly = candidateWindows.first { $0.kind == .weekly }
        return (fiveHour, weekly)
    }

    public func mostConstrainedWindow(antigravityGroup: AntigravityGroupPreference) -> QuotaWindow? {
        let pair = resolvedWindows(antigravityGroup: antigravityGroup)
        let list = [pair.fiveHour, pair.weekly].compactMap { $0 }
        if !list.isEmpty {
            return list.min { $0.remainingPercent < $1.remainingPercent }
        }
        return windows.min { $0.remainingPercent < $1.remainingPercent }
    }

    public func preferredBalance(currencyPreference: String) -> DeepSeekBalanceItem? {
        let pref = currencyPreference.uppercased()
        if pref != "AUTO", let exact = balances.first(where: { $0.currency == pref }) {
            return exact
        }
        if let positive = balances.first(where: { $0.numericTotal > 0 }) {
            return positive
        }
        if let cny = balances.first(where: { $0.currency == "CNY" }) {
            return cny
        }
        return balances.first
    }

    private func filterAntigravityWindows(preference: AntigravityGroupPreference) -> [QuotaWindow] {
        guard !windows.isEmpty else { return [] }
        switch preference {
        case .gemini:
            let filtered = windows.filter { ($0.groupID ?? "").contains("gemini") || ($0.groupName ?? "").localizedCaseInsensitiveContains("gemini") }
            return filtered.isEmpty ? windows : filtered
        case .thirdParty:
            let filtered = windows.filter { ($0.groupID ?? "").contains("3p") || ($0.groupName ?? "").localizedCaseInsensitiveContains("claude") }
            return filtered.isEmpty ? windows : filtered
        case .auto:
            let grouped = Dictionary(grouping: windows) { $0.groupName ?? "" }
            guard grouped.count > 1 else { return windows }
            let tightestGroup = grouped.min { lhs, rhs in
                let lhsMin = lhs.value.map(\.remainingPercent).min() ?? 100
                let rhsMin = rhs.value.map(\.remainingPercent).min() ?? 100
                return lhsMin < rhsMin
            }
            return tightestGroup?.value ?? windows
        }
    }
}

public enum TimeFormatting {
    public static func compactCountdown(until target: Date, from now: Date) -> String {
        let seconds = Int(target.timeIntervalSince(now))
        guard seconds > 0 else { return "即将重置" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return hours > 0 ? "\(days)d\(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h\(minutes)m" : "\(hours)h"
        }
        return "\(max(1, minutes))m"
    }

    public static func detailedCountdown(until target: Date, from now: Date) -> String {
        let seconds = Int(target.timeIntervalSince(now))
        guard seconds > 0 else { return "即将重置" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return "\(days)天 \(hours)小时后重置"
        }
        if hours > 0 {
            return "\(hours)小时 \(minutes)分后重置"
        }
        return "\(max(1, minutes))分钟后重置"
    }

    public static func compactResetClock(_ date: Date, kind: WindowKind, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if kind == .fiveHour || Calendar.current.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "MM-dd HH:mm"
        }
        return formatter.string(from: date)
    }

    public static func fullDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    public static func timeWithSeconds(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
