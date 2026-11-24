import AppKit
import SwiftUI
import UsageCenterCore

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: UsageCenterStore

    init(store: UsageCenterStore) {
        self.store = store
    }

    func show() {
        if let existing = window {
            store.refreshLaunchAtLoginStatus()
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let rootView = SettingsWindowView(store: store)
        let hosting = NSHostingController(rootView: rootView)
        let win = NSWindow(contentViewController: hosting)
        win.title = "UsageCenter 设置"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.setContentSize(NSSize(width: 820, height: 700))
        win.minSize = NSSize(width: 740, height: 600)
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win

        store.refreshLaunchAtLoginStatus()
        win.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class UsageCenterAppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageCenterStore?
    private var statusBarController: StatusBarController?
    private var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        installMainMenuForShortcuts()

        let store = UsageCenterStore()
        let settings = SettingsWindowController(store: store)
        let statusBar = StatusBarController(store: store) {
            settings.show()
        }

        self.store = store
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
            // 1. Deterministic Parser Self-Checks
            let claudeSample = Data("""
            {"is_error":false,"result":"Current session: 14% used · resets Nov 25 at 4:30am (Asia/Shanghai)\\nCurrent week (all models): 32% used · resets Nov 28 at 10pm (Asia/Shanghai)"}
            """.utf8)
            let claudeSnap = try ClaudeCLIParser.parseUsageOutput(claudeSample)
            precondition(claudeSnap.windows.count == 2 && claudeSnap.windows[0].usedPercent == 14)

            let codexSnap = try CodexCLIParser.parse(
                accountResult: ["account": ["type": "chatgpt", "planType": "plus"]],
                rateLimitsResult: ["rateLimits": [
                    "limitId": "codex",
                    "primary": ["usedPercent": 6, "windowDurationMins": 300, "resetsAt": 1_795_551_747],
                    "secondary": ["usedPercent": 16, "windowDurationMins": 10_080, "resetsAt": 1_795_690_346]
                ]]
            )
            precondition(codexSnap.windows.count == 2 && codexSnap.windows[0].remainingPercent == 94)

            let agySample = Data("""
            {"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"gemini-5h","window":"5h","remaining_fraction":0.92,"reset_time":"2026-11-24T20:22:25Z"},{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.98,"reset_time":"2026-12-01T15:22:25Z"}]}]}}}
            """.utf8)
            let agySnap = try AntigravityCLIParser.parseUsageOutput(agySample)
            precondition(agySnap.windows.count == 2 && agySnap.windows[0].usedPercent == 8)

            let dsSample = Data("""
            {"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"48.60","granted_balance":"8.60","topped_up_balance":"40.00"}]}
            """.utf8)
            let dsSnap = try DeepSeekCLIParser.parseBalanceOutput(dsSample)
            precondition(dsSnap.preferredBalance(currencyPreference: "AUTO")?.formattedTotal == "¥48.60")
            print("[OK] Parser unit assertions passed")
        } catch {
            fputs("[FAIL] Parser assertion failed: \(error)\n", stderr)
            exit(1)
        }

        // 2. Live Local CLI Integration Probe
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let prefs = UsageCenterPreferences()
            for provider in ProviderID.allCases {
                do {
                    let snap = try await ProviderUsageFetcher.fetch(provider: provider, preferences: prefs)
                    if provider == .deepseek {
                        let bal = snap.preferredBalance(currencyPreference: "AUTO")?.formattedTotal ?? "N/A"
                        print("[LIVE OK] \(provider.displayName): \(bal)")
                    } else {
                        let pair = snap.resolvedWindows(antigravityGroup: .auto)
                        let s5 = pair.fiveHour.map { "5h used \($0.usedPercent)%" } ?? "no-5h"
                        let s7 = pair.weekly.map { "weekly used \($0.usedPercent)%" } ?? "no-weekly"
                        print("[LIVE OK] \(provider.displayName) (\(snap.accountLabel ?? "-")): \(s5), \(s7) [total windows: \(snap.windows.count)]")
                    }
                } catch {
                    print("[LIVE INFO] \(provider.displayName): \(error.localizedDescription)")
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }
}
