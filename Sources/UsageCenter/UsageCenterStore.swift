import AppKit
import Combine
import Foundation
import ServiceManagement
import UserNotifications
import UsageCenterCore

enum SettingsCategory: String, CaseIterable, Identifiable {
    case menuAndPopover
    case cliAndAccounts
    case general
    case notifications
    case history
    case developer
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuAndPopover: return "菜单栏与弹窗"
        case .cliAndAccounts: return "CLI 与账户"
        case .general: return "通用"
        case .notifications: return "通知"
        case .history: return "历史与存储"
        case .developer: return "开发者"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .menuAndPopover: return "menubar.rectangle"
        case .cliAndAccounts: return "terminal"
        case .general: return "gearshape"
        case .notifications: return "bell"
        case .history: return "externaldrive"
        case .developer: return "hammer"
        case .about: return "info.circle"
        }
    }
}

@MainActor
final class UsageCenterStore: ObservableObject {
    private static let preferencesKey = "UsageCenter.preferences.v3"
    private let historyStore = UsageHistoryStore()

    @Published var preferences: UsageCenterPreferences {
        didSet {
            guard preferences != oldValue else { return }
            persistPreferences()
            if preferences.refreshIntervalSeconds != oldValue.refreshIntervalSeconds {
                rescheduleTimer()
            }
            if preferences.historyRetention != oldValue.historyRetention {
                historyStore.applyRetention(preferences.historyRetention)
                reloadHistoryMetadata()
            }
        }
    }

    @Published private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
    @Published var activeProvider: ProviderID = .claude
    @Published var selectedSettingsCategory: SettingsCategory = .menuAndPopover

    // Detailed History Window State (CodexMeter parity)
    @Published var historyProvider: ProviderID = .chatgpt
    @Published var historyWindowID: String?
    @Published var historyMode: HistoryQueryMode = .currentCycle
    @Published var historyCalendarUnit: HistoryCalendarUnit = .week
    @Published var historyCalendarOffset: Int = 0
    @Published var tokenRange: TokenHistoryRange = .days30
    @Published var hoveredQuotaPointID: String?
    @Published var hoveredTokenDate: Date?
    @Published var showsClearHistoryAlert: Bool = false

    @Published private(set) var historySamples: [QuotaHistoryPoint] = []
    @Published private(set) var persistedTokenActivity: TokenActivitySnapshot?
    @Published private(set) var historyStorageBytes: Int64 = 0
    @Published var deepSeekAPIKeyInput: String = ""
    @Published private(set) var hasStoredDeepSeekKey: Bool = false
    @Published private(set) var hasDSHLocalLogin: Bool = false
    @Published private(set) var launchAtLoginEnabled: Bool = false
    @Published var statusBannerMessage: String?

    private var refreshTimer: Timer?
    private var inFlightProviders = Set<ProviderID>()
    private var isPopoverOpen = false
    private var alertedWindowKeys = Set<String>()

    init() {
        let loadedPrefs: UsageCenterPreferences
        if let raw = UserDefaults.standard.data(forKey: Self.preferencesKey),
           let decoded = try? JSONDecoder().decode(UsageCenterPreferences.self, from: raw) {
            var normalized = decoded
            normalized.sections = UsageCenterPreferences.normalizedSections(decoded.sections)
            normalized.popoverSections = UsageCenterPreferences.normalizedPopoverSections(decoded.popoverSections)
            loadedPrefs = normalized
        } else {
            loadedPrefs = UsageCenterPreferences()
        }
        self.preferences = loadedPrefs

        for provider in ProviderID.allCases {
            snapshots[provider] = ProviderSnapshot(provider: provider, isLoading: true)
        }

        if let firstEnabled = loadedPrefs.enabledSections.first?.provider {
            activeProvider = firstEnabled
            historyProvider = firstEnabled
        }

        let storedKey = KeychainHelper.readDeepSeekAPIKey() ?? ""
        self.deepSeekAPIKeyInput = storedKey
        self.hasStoredDeepSeekKey = !storedKey.isEmpty
        self.hasDSHLocalLogin = (DSHCredentialReader.readDefaultGrant() != nil)
        self.refreshLaunchAtLoginStatus()
        self.reloadHistoryMetadata()

        rescheduleTimer()
        Task { [weak self] in
            await self?.refreshAll()
        }
    }

    func snapshot(for provider: ProviderID) -> ProviderSnapshot {
        snapshots[provider] ?? ProviderSnapshot(provider: provider)
    }

    func effectiveTokenActivity() -> TokenActivitySnapshot? {
        snapshots[.chatgpt]?.tokenActivity ?? persistedTokenActivity
    }

    func isRefreshing(_ provider: ProviderID) -> Bool {
        inFlightProviders.contains(provider)
    }

    func setPopoverVisible(_ visible: Bool) {
        guard isPopoverOpen != visible else { return }
        isPopoverOpen = visible
        rescheduleTimer()
    }

    func detectedCLIPath(for provider: ProviderID) -> String? {
        if provider == .deepseek, DSHCredentialReader.readDefaultGrant() != nil {
            return "~/.dsh/.credentials.yaml"
        }
        let custom = preferences.config(for: provider).customCLIPath
        return ExecutableLocator.locate(
            binaryName: provider.defaultBinaryName,
            customPath: custom
        )?.path
    }

    func refreshDSHLoginStatus() {
        hasDSHLocalLogin = (DSHCredentialReader.readDefaultGrant() != nil)
    }

    func saveDeepSeekKey() {
        let ok = KeychainHelper.saveDeepSeekAPIKey(deepSeekAPIKeyInput)
        hasStoredDeepSeekKey = !deepSeekAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ok
        statusBannerMessage = ok ? "已保存备用 API Key" : "钥匙串保存失败"
        Task { await refresh(provider: .deepseek) }
    }

    func clearDeepSeekKey() {
        _ = KeychainHelper.deleteDeepSeekAPIKey()
        deepSeekAPIKeyInput = ""
        hasStoredDeepSeekKey = false
        Task { await refresh(provider: .deepseek) }
    }

    func refreshAll() async {
        refreshDSHLoginStatus()
        let targets = preferences.enabledSections.map(\.provider)
        await withTaskGroup(of: Void.self) { group in
            for provider in targets {
                group.addTask { [weak self] in
                    await self?.refresh(provider: provider)
                }
            }
        }
    }

    func refresh(provider: ProviderID) async {
        guard !inFlightProviders.contains(provider) else { return }
        inFlightProviders.insert(provider)
        defer { inFlightProviders.remove(provider) }

        if provider == .deepseek {
            refreshDSHLoginStatus()
        }

        var previous = snapshot(for: provider)
        if !previous.hasData {
            previous.isLoading = true
        }
        previous.errorMessage = nil
        snapshots[provider] = previous

        let currentPrefs = preferences
        let keyOverride = provider == .deepseek ? deepSeekAPIKeyInput : nil

        do {
            var fresh = try await ProviderUsageFetcher.fetch(
                provider: provider,
                preferences: currentPrefs,
                deepSeekKeyOverride: keyOverride
            )
            if fresh.tokenActivity == nil, let oldTokens = previous.tokenActivity ?? persistedTokenActivity {
                fresh.tokenActivity = oldTokens
            }
            snapshots[provider] = fresh

            if historyStore.record(snapshot: fresh, retention: currentPrefs.historyRetention) {
                reloadHistoryMetadata()
            }
            evaluateNotifications(for: fresh)
        } catch {
            var failed = snapshot(for: provider)
            failed.isLoading = false
            failed.isStale = failed.hasData
            failed.errorMessage = error.localizedDescription
            snapshots[provider] = failed
        }
    }

    // MARK: - History Queries

    func reloadHistoryMetadata() {
        historySamples = historyStore.allSamples()
        persistedTokenActivity = historyStore.storedTokenActivity()
        historyStorageBytes = historyStore.storageSizeBytes()
    }

    func windowSamples(for provider: ProviderID, windowID: String?) -> [QuotaHistoryPoint] {
        let providerAll = historySamples.filter { $0.provider == provider }
        if provider == .deepseek {
            return providerAll
        }
        let targetID = windowID ?? defaultHistoryWindowID(for: provider)
        guard let targetID else { return providerAll }
        return providerAll.filter { $0.windowID == targetID }
    }

    func activeWindowObject(for provider: ProviderID, windowID: String?) -> QuotaWindow? {
        let snap = snapshot(for: provider)
        let targetID = windowID ?? defaultHistoryWindowID(for: provider)
        if let targetID, let found = snap.windows.first(where: { $0.id == targetID }) {
            return found
        }
        let pair = snap.resolvedWindows(antigravityGroup: preferences.antigravityGroup)
        return pair.weekly ?? pair.fiveHour ?? snap.windows.first
    }

    func defaultHistoryWindowID(for provider: ProviderID) -> String? {
        let snap = snapshot(for: provider)
        let pair = snap.resolvedWindows(antigravityGroup: preferences.antigravityGroup)
        if let weekly = pair.weekly { return weekly.id }
        if let five = pair.fiveHour { return five.id }
        return snap.windows.first?.id ?? historySamples.last(where: { $0.provider == provider })?.windowID
    }

    func generateDemoHistory() {
        historyStore.populateDemoHistory()
        reloadHistoryMetadata()
    }

    func clearHistory() {
        historyStore.clearAll()
        reloadHistoryMetadata()
    }

    func exportHistoryCSVInteractive() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "UsageCenter-History.csv"
        if panel.runModal() == .OK, let url = panel.url {
            try? historyStore.exportCSV().write(to: url, options: .atomic)
        }
    }

    // MARK: - Notifications

    func setNotificationsEnabled(_ enabled: Bool) {
        guard enabled else {
            preferences.notificationsEnabled = false
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.preferences.notificationsEnabled = granted
                if !granted {
                    self.statusBannerMessage = "未授予通知权限，请在系统设置 → 通知中开启"
                }
            }
        }
    }

    private func evaluateNotifications(for snap: ProviderSnapshot) {
        guard preferences.notificationsEnabled else { return }
        let now = Date()
        for win in snap.windows {
            let key = "\(snap.provider.rawValue):\(win.id)"
            let low = win.remainingPercent < preferences.lowQuotaThreshold
            let over = preferences.notifyOnOverPace && win.pace(at: now) == .overPace
            if low || over {
                guard alertedWindowKeys.insert(key).inserted else { continue }
                let content = UNMutableNotificationContent()
                content.title = "\(snap.provider.displayName) · \(win.title)"
                content.body = low
                    ? "剩余配额 \(win.remainingPercent)%"
                    : "消耗速度超出时间进度（剩余 \(win.remainingPercent)%）"
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
            } else {
                alertedWindowKeys.remove(key)
            }
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginStatus()
        } catch {
            statusBannerMessage = "请从 /Applications/UsageCenter.app 开启登录自启"
            refreshLaunchAtLoginStatus()
        }
    }

    func restoreDefaultPreferences() {
        preferences = UsageCenterPreferences()
    }

    private func persistPreferences() {
        guard let encoded = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.preferencesKey)
    }

    private func rescheduleTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        let baseSeconds = preferences.refreshIntervalSeconds
        guard baseSeconds > 0 else { return }
        let effectiveSeconds = isPopoverOpen ? min(10, baseSeconds) : baseSeconds

        let timer = Timer(timeInterval: TimeInterval(effectiveSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAll()
            }
        }
        timer.tolerance = isPopoverOpen ? 1 : 5
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }
}
