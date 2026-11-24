import AppKit
import Combine
import Foundation
import ServiceManagement
import UserNotifications
import UsageCenterCore

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case menuAndPopover
    case cliAndAccounts
    case notifications
    case history
    case developer
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .menuAndPopover: return "菜单栏与弹窗"
        case .cliAndAccounts: return "CLI 与账户"
        case .notifications: return "通知提醒"
        case .history: return "历史与存储"
        case .developer: return "开发者选项"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .menuAndPopover: return "menubar.rectangle"
        case .cliAndAccounts: return "terminal"
        case .notifications: return "bell"
        case .history: return "externaldrive"
        case .developer: return "hammer"
        case .about: return "info.circle"
        }
    }
}

@MainActor
final class UsageCenterStore: ObservableObject {
    private static let preferencesKey = "UsageCenter.preferences.v2"
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
    @Published var selectedSettingsCategory: SettingsCategory? = .menuAndPopover
    @Published var historyProvider: ProviderID = .chatgpt
    @Published var historyWindowID: String?
    @Published var historyRange: HistoryTimeRange = .currentCycle
    @Published var showsClearHistoryAlert: Bool = false

    @Published private(set) var historySamples: [QuotaHistoryPoint] = []
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
            let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh/.credentials.yaml").path
            return path
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
        statusBannerMessage = ok ? "已保存备用 DeepSeek API Key 至系统钥匙串" : "钥匙串写入失败"
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
            // Preserve previous tokenActivity if the latest refresh omitted it
            if fresh.tokenActivity == nil, let oldTokens = previous.tokenActivity {
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

    // MARK: - History Helpers

    func reloadHistoryMetadata() {
        historySamples = historyStore.allSamples()
        historyStorageBytes = historyStore.storageSizeBytes()
    }

    func historyPoints(for provider: ProviderID, windowID: String?, range: HistoryTimeRange) -> [QuotaHistoryPoint] {
        let cutoff = Date().addingTimeInterval(-range.lookbackSeconds)
        let providerSamples = historySamples.filter { $0.provider == provider && $0.timestamp >= cutoff }
        if provider == .deepseek {
            return providerSamples
        }
        let resolvedID = windowID ?? defaultHistoryWindowID(for: provider)
        guard let resolvedID else { return providerSamples }
        return providerSamples.filter { $0.windowID == resolvedID }
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
            let data = historyStore.exportCSV()
            try? data.write(to: url, options: .atomic)
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
                    self.statusBannerMessage = "系统未授予通知权限，请在系统设置 → 通知中允许 UsageCenter"
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
                    ? "剩余配额仅 \(win.remainingPercent)%（低于阈值 \(preferences.lowQuotaThreshold)%）"
                    : "当前消耗速度超出时间进度（剩余配额 \(win.remainingPercent)%）"
                let req = UNNotificationRequest(identifier: key, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(req)
            } else {
                alertedWindowKeys.remove(key)
            }
        }
    }

    // MARK: - Login & Persistence

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
            statusBannerMessage = "开机自启需从 /Applications/UsageCenter.app 启动设置"
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
