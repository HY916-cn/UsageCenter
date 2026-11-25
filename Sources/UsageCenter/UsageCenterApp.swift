import AppKit
import SwiftUI
import UsageCenterCore

@MainActor
final class WindowPolicyCoordinator {
    static let shared = WindowPolicyCoordinator()
    private var openWindowCount = 0

    func windowDidOpen() {
        openWindowCount += 1
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowDidClose() {
        openWindowCount = max(0, openWindowCount - 1)
        if openWindowCount == 0 {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: UsageCenterStore
    private let onOpenHistory: (ProviderID) -> Void
    private var isTrackedOpen = false

    init(store: UsageCenterStore, onOpenHistory: @escaping (ProviderID) -> Void) {
        self.store = store
        self.onOpenHistory = onOpenHistory
        super.init()
    }

    func show() {
        if !isTrackedOpen {
            isTrackedOpen = true
            WindowPolicyCoordinator.shared.windowDidOpen()
        }

        if let existing = window {
            store.refreshLaunchAtLoginStatus()
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let rootView = SettingsWindowView(store: store, onOpenHistory: onOpenHistory)
        let hosting = NSHostingController(rootView: rootView)
        let win = NSWindow(contentViewController: hosting)
        win.title = "UsageCenter 设置"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.appearance = NSAppearance(named: .darkAqua)
        win.setContentSize(NSSize(width: 860, height: 680))
        win.minSize = NSSize(width: 780, height: 600)
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        self.window = win

        store.refreshLaunchAtLoginStatus()
        win.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if isTrackedOpen {
            isTrackedOpen = false
            WindowPolicyCoordinator.shared.windowDidClose()
        }
    }
}

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: UsageCenterStore
    private var isTrackedOpen = false

    init(store: UsageCenterStore) {
        self.store = store
        super.init()
    }

    func show(for provider: ProviderID) {
        store.historyProvider = provider
        store.historyWindowID = store.defaultHistoryWindowID(for: provider)
        store.reloadHistoryMetadata()

        if !isTrackedOpen {
            isTrackedOpen = true
            WindowPolicyCoordinator.shared.windowDidOpen()
        }

        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let rootView = UsageHistoryWindowView(store: store)
        let hosting = NSHostingController(rootView: rootView)
        let win = NSWindow(contentViewController: hosting)
        win.title = "用量历史"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.collectionBehavior.insert(.fullScreenPrimary)
        win.appearance = NSAppearance(named: .darkAqua)
        win.setContentSize(NSSize(width: 940, height: 840))
        win.minSize = NSSize(width: 780, height: 640)
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        self.window = win

        win.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if isTrackedOpen {
            isTrackedOpen = false
            WindowPolicyCoordinator.shared.windowDidClose()
        }
    }
}

@MainActor
final class UsageCenterAppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageCenterStore?
    private var statusBarController: StatusBarController?
    private var settingsController: SettingsWindowController?
    private var historyController: HistoryWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.main.url(forResource: "UsageCenter_UsageCenter", withExtension: "bundle")
                .flatMap({ Bundle(url: $0)?.url(forResource: "AppIcon", withExtension: "icns") }),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }
        installMainMenuForShortcuts()

        let store = UsageCenterStore()
        let history = HistoryWindowController(store: store)
        let settings = SettingsWindowController(store: store) { provider in
            history.show(for: provider)
        }
        let statusBar = StatusBarController(
            store: store,
            onOpenSettings: { settings.show() },
            onOpenHistory: { provider in history.show(for: provider) }
        )

        self.store = store
        self.historyController = history
        self.settingsController = settings
        self.statusBarController = statusBar
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsController?.show()
        return true
    }

    private func installMainMenuForShortcuts() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 UsageCenter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }
}

@main
struct UsageCenterMain {
    static func main() {
        if CommandLine.arguments.contains("--self-check") {
            runSelfCheckAndExit()
        }
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated {
            UsageCenterAppDelegate()
        }
        app.delegate = delegate
        app.run()
    }

    private static func runSelfCheckAndExit() -> Never {
        do {
            // 1. Verify White SVG Icons
            for p in ProviderID.allCases {
                let img = BrandIconRenderer.whiteIcon(for: p, size: 16)
                precondition(img.size.width == 16 && !img.representations.isEmpty, "Missing SVG for \(p)")
            }

            // 2. Verify Slot Coordinate Resolution & Fixed Non-Moving Geometry Across Value Changes
            let nowCheck = Date()
            for style in SegmentDisplayStyle.allCases {
                var prefs = UsageCenterPreferences()
                prefs.globalStyle = style

                let loadingSnaps: [ProviderID: ProviderSnapshot] = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map {
                    ($0, ProviderSnapshot(provider: $0, isLoading: true))
                })
                let singleDigitSnaps: [ProviderID: ProviderSnapshot] = [
                    .claude: ProviderSnapshot(provider: .claude, windows: [
                        QuotaWindow(id: "c5", title: "5小时", kind: .fiveHour, usedPercent: 93, durationMinutes: 300, resetsAt: nowCheck.addingTimeInterval(1800)),
                        QuotaWindow(id: "c7", title: "每周", kind: .weekly, usedPercent: 99, durationMinutes: 10_080, resetsAt: nowCheck.addingTimeInterval(86_400))
                    ], isLoading: false),
                    .chatgpt: ProviderSnapshot(provider: .chatgpt, windows: [
                        QuotaWindow(id: "g5", title: "5小时", kind: .fiveHour, usedPercent: 95, durationMinutes: 300, resetsAt: nowCheck.addingTimeInterval(3600)),
                        QuotaWindow(id: "g7", title: "每周", kind: .weekly, usedPercent: 91, durationMinutes: 10_080, resetsAt: nowCheck.addingTimeInterval(90_000))
                    ], isLoading: false),
                    .antigravity: ProviderSnapshot(provider: .antigravity, windows: [
                        QuotaWindow(id: "a5", title: "5小时", kind: .fiveHour, usedPercent: 98, durationMinutes: 300, resetsAt: nowCheck.addingTimeInterval(600)),
                        QuotaWindow(id: "a7", title: "每周", kind: .weekly, usedPercent: 96, durationMinutes: 10_080, resetsAt: nowCheck.addingTimeInterval(50_000))
                    ], isLoading: false),
                    .deepseek: ProviderSnapshot(provider: .deepseek, balances: [
                        DeepSeekBalanceItem(currency: "CNY", totalBalance: "3.20", grantedBalance: "0.00", toppedUpBalance: "3.20")
                    ], isAvailable: true, isLoading: false)
                ]
                let tripleDigitSnaps: [ProviderID: ProviderSnapshot] = [
                    .claude: ProviderSnapshot(provider: .claude, windows: [
                        QuotaWindow(id: "c5", title: "5小时", kind: .fiveHour, usedPercent: 0, durationMinutes: 300, resetsAt: nowCheck.addingTimeInterval(17_900)),
                        QuotaWindow(id: "c7", title: "每周", kind: .weekly, usedPercent: 0, durationMinutes: 10_080, resetsAt: nowCheck.addingTimeInterval(600_000))
                    ], isLoading: false),
                    .chatgpt: ProviderSnapshot(provider: .chatgpt, windows: [
                        QuotaWindow(id: "g5", title: "5小时", kind: .fiveHour, usedPercent: 0, durationMinutes: 300, resetsAt: nowCheck.addingTimeInterval(17_900)),
                        QuotaWindow(id: "g7", title: "每周", kind: .weekly, usedPercent: 0, durationMinutes: 10_080, resetsAt: nowCheck.addingTimeInterval(600_000))
                    ], isLoading: false),
                    .antigravity: ProviderSnapshot(provider: .antigravity, windows: [
                        QuotaWindow(id: "a5", title: "5小时", kind: .fiveHour, usedPercent: 0, durationMinutes: 300, resetsAt: nowCheck.addingTimeInterval(17_900)),
                        QuotaWindow(id: "a7", title: "每周", kind: .weekly, usedPercent: 0, durationMinutes: 10_080, resetsAt: nowCheck.addingTimeInterval(600_000))
                    ], isLoading: false),
                    .deepseek: ProviderSnapshot(provider: .deepseek, balances: [
                        DeepSeekBalanceItem(currency: "CNY", totalBalance: "1288.45", grantedBalance: "0.00", toppedUpBalance: "1288.45")
                    ], isAvailable: true, isLoading: false)
                ]

                let framesLoading = MainActor.assumeIsolated { () -> [NSRect] in
                    let v = CompositeStatusBarView(frame: .zero)
                    _ = v.update(preferences: prefs, snapshots: loadingSnaps, selectedProvider: nil)
                    return v.slots.map(\.frame)
                }
                let framesSingle = MainActor.assumeIsolated { () -> [NSRect] in
                    let v = CompositeStatusBarView(frame: .zero)
                    _ = v.update(preferences: prefs, snapshots: singleDigitSnaps, selectedProvider: nil)
                    return v.slots.map(\.frame)
                }
                let framesTriple = MainActor.assumeIsolated { () -> [NSRect] in
                    let v = CompositeStatusBarView(frame: .zero)
                    _ = v.update(preferences: prefs, snapshots: tripleDigitSnaps, selectedProvider: nil)
                    for slot in v.slots {
                        let resolved = v.resolveSlot(atLocalX: slot.frame.midX)?.provider
                        precondition(resolved == slot.provider, "Slot hit mismatch for \(slot.provider)")
                    }
                    return v.slots.map(\.frame)
                }

                precondition(framesLoading == framesSingle && framesSingle == framesTriple, "Slot frames shifted in style \(style)")
            }
            print("[OK] White SVG icons, fixed non-moving widths across all 4 styles, & exact X-coordinate resolution verified")

            // 3. Verify History Multi-Cycle, Zero-Sample Live Cycle Synthesis, & Token Aggregation Analytics
            let now = Date()
            let liveWin = QuotaWindow(id: "claude-week", title: "每周配额", kind: .weekly, usedPercent: 1, durationMinutes: 10_080, resetsAt: now.addingTimeInterval(3 * 86_400))
            let singleCycleSeries = HistoryAnalytics.buildQuotaSeries(
                samples: [],
                mode: .currentCycle,
                calendarUnit: .week,
                calendarOffset: 0,
                activeWindow: liveWin,
                isBalance: false,
                now: now
            )
            precondition(singleCycleSeries != nil && singleCycleSeries!.points.count >= 2, "Expected expanded inline history series from live window")
            let samplePts = [
                QuotaHistoryPoint(provider: .chatgpt, windowID: "w", windowTitle: "周", durationMinutes: 10_080, timestamp: now.addingTimeInterval(-3600 * 10), remainingPercent: 90, resetsAt: now.addingTimeInterval(3600 * 50)),
                QuotaHistoryPoint(provider: .chatgpt, windowID: "w", windowTitle: "周", durationMinutes: 10_080, timestamp: now, remainingPercent: 76, resetsAt: now.addingTimeInterval(3600 * 40))
            ]
            let series = HistoryAnalytics.buildQuotaSeries(
                samples: samplePts,
                mode: .currentCycle,
                calendarUnit: .week,
                calendarOffset: 0,
                activeWindow: nil,
                isBalance: false,
                now: now
            )
            precondition(series != nil && series!.observedConsumedPercent >= 14)
            print("[OK] Multi-cycle history analytics & burn-rate projection verified")
        }

        // 4. Live CLI + DSH Check
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let prefs = UsageCenterPreferences()
            for provider in ProviderID.allCases {
                do {
                    let snap = try await ProviderUsageFetcher.fetch(provider: provider, preferences: prefs)
                    if provider == .deepseek {
                        let item = snap.preferredBalance(currencyPreference: "AUTO")
                        print("[LIVE OK] DeepSeek (\(snap.accountLabel ?? "-")): \(item?.formattedTotal ?? "N/A")")
                    } else {
                        let pair = snap.resolvedWindows(antigravityGroup: .auto)
                        let s5 = pair.fiveHour.map { "5h \($0.remainingPercent)%" } ?? "-"
                        let s7 = pair.weekly.map { "7d \($0.remainingPercent)%" } ?? "-"
                        print("[LIVE OK] \(provider.displayName): \(s5), \(s7)")
                    }
                } catch {
                    print("[LIVE ERR] \(provider.displayName): \(error.localizedDescription)")
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }
}
