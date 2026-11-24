import AppKit
import Combine
import Foundation
import ServiceManagement
import UsageCenterCore

@MainActor
final class UsageCenterStore: ObservableObject {
    private static let preferencesKey = "UsageCenter.preferences.v1"

    @Published var preferences: UsageCenterPreferences {
        didSet {
            guard preferences != oldValue else { return }
            persistPreferences()
            if preferences.refreshIntervalSeconds != oldValue.refreshIntervalSeconds {
                rescheduleTimer()
            }
        }
    }

    @Published private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
    @Published var activeProvider: ProviderID = .claude
    @Published var selectedSettingsTab: SettingsTab = .layout
    @Published var deepSeekAPIKeyInput: String = ""
    @Published private(set) var hasStoredDeepSeekKey: Bool = false
    @Published private(set) var launchAtLoginEnabled: Bool = false
    @Published var statusBannerMessage: String?

    private var refreshTimer: Timer?
    private var inFlightProviders = Set<ProviderID>()

    init() {
        let loadedPrefs: UsageCenterPreferences
        if let raw = UserDefaults.standard.data(forKey: Self.preferencesKey),
           let decoded = try? JSONDecoder().decode(UsageCenterPreferences.self, from: raw) {
            var normalized = decoded
            normalized.sections = UsageCenterPreferences.normalizedSections(decoded.sections)
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
        }

        let storedKey = KeychainHelper.readDeepSeekAPIKey() ?? ""
        self.deepSeekAPIKeyInput = storedKey
        self.hasStoredDeepSeekKey = !storedKey.isEmpty
        self.refreshLaunchAtLoginStatus()

        rescheduleTimer()
        Task { [weak self] in
            await self?.refreshAll()
        }
    }

    func snapshot(for provider: ProviderID) -> ProviderSnapshot {
        snapshots[provider] ?? ProviderSnapshot(provider: provider)
    }

    var isAnyRefreshing: Bool {
        !inFlightProviders.isEmpty
    }

    func detectedCLIPath(for provider: ProviderID) -> String? {
        let custom = preferences.config(for: provider).customCLIPath
        return ExecutableLocator.locate(
            binaryName: provider.defaultBinaryName,
            customPath: custom
        )?.path
    }

    func saveDeepSeekKey() {
        let ok = KeychainHelper.saveDeepSeekAPIKey(deepSeekAPIKeyInput)
        hasStoredDeepSeekKey = !deepSeekAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ok
        statusBannerMessage = ok ? "已将 DeepSeek API Key 安全保存至系统钥匙串" : "保存钥匙串失败，请检查系统权限"
        Task {
            await refresh(provider: .deepseek)
        }
    }

    func clearDeepSeekKey() {
        _ = KeychainHelper.deleteDeepSeekAPIKey()
        deepSeekAPIKeyInput = ""
        hasStoredDeepSeekKey = false
        statusBannerMessage = "已清除钥匙串中的 DeepSeek API Key"
        Task {
            await refresh(provider: .deepseek)
        }
    }

    func refreshAll() async {
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

        var previous = snapshot(for: provider)
        if !previous.hasData {
            previous.isLoading = true
        }
        previous.errorMessage = nil
        snapshots[provider] = previous

        let currentPrefs = preferences
        let keyOverride = provider == .deepseek ? deepSeekAPIKeyInput : nil

        do {
            let fresh = try await ProviderUsageFetcher.fetch(
                provider: provider,
                preferences: currentPrefs,
                deepSeekKeyOverride: keyOverride
            )
            snapshots[provider] = fresh
        } catch {
            var failed = snapshot(for: provider)
            failed.isLoading = false
            failed.isStale = failed.hasData
            failed.errorMessage = error.localizedDescription
            snapshots[provider] = failed
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
            statusBannerMessage = "开机自启需要在打包签名后的 UsageCenter.app 中启用"
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
        let seconds = preferences.refreshIntervalSeconds
        guard seconds > 0 else { return }

        let timer = Timer(timeInterval: TimeInterval(seconds), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAll()
            }
        }
        timer.tolerance = max(2, Double(seconds) * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }
}
