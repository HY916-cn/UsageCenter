import Foundation

public struct QuotaHistoryPoint: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let provider: ProviderID
    public let windowID: String
    public let windowTitle: String
    public let timestamp: Date
    public let remainingPercent: Int
    public let resetsAt: Date?
    public let balanceAmount: Double?
    public let currency: String?

    public init(
        id: UUID = UUID(),
        provider: ProviderID,
        windowID: String,
        windowTitle: String,
        timestamp: Date,
        remainingPercent: Int = 0,
        resetsAt: Date? = nil,
        balanceAmount: Double? = nil,
        currency: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.windowID = windowID
        self.windowTitle = windowTitle
        self.timestamp = timestamp
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.balanceAmount = balanceAmount
        self.currency = currency
    }
}

public enum HistoryTimeRange: String, CaseIterable, Codable, Identifiable, Sendable {
    case currentCycle
    case days7
    case days14
    case days30

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .currentCycle: return "当前周期"
        case .days7: return "近 7 天"
        case .days14: return "近 14 天"
        case .days30: return "近 30 天"
        }
    }

    public var lookbackSeconds: TimeInterval {
        switch self {
        case .currentCycle: return 7 * 86_400
        case .days7: return 7 * 86_400
        case .days14: return 14 * 86_400
        case .days30: return 30 * 86_400
        }
    }
}

public final class UsageHistoryStore: @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL
    private var samples: [QuotaHistoryPoint] = []

    public static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("UsageCenter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage_history.json")
    }

    public init(fileURL: URL = UsageHistoryStore.defaultStorageURL()) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([QuotaHistoryPoint].self, from: data) {
            self.samples = decoded
        }
    }

    public func allSamples() -> [QuotaHistoryPoint] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    public func storageSizeBytes() -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    @discardableResult
    public func record(snapshot: ProviderSnapshot, retention: HistoryRetentionPolicy, now: Date = Date()) -> Bool {
        guard !snapshot.isStale, snapshot.hasData else { return false }

        lock.lock()
        defer { lock.unlock() }

        var appended = false

        if snapshot.provider == .deepseek {
            if let bal = snapshot.balances.first {
                let winID = "deepseek-\(bal.currency.lowercased())"
                let last = samples.last { $0.provider == .deepseek && $0.windowID == winID }
                let changed = last == nil
                    || abs((last?.balanceAmount ?? -1) - bal.numericTotal) >= 0.005
                    || now.timeIntervalSince(last!.timestamp) >= 15 * 60
                if changed {
                    samples.append(QuotaHistoryPoint(
                        provider: .deepseek,
                        windowID: winID,
                        windowTitle: "API 余额 (\(bal.currency))",
                        timestamp: now,
                        balanceAmount: bal.numericTotal,
                        currency: bal.currency
                    ))
                    appended = true
                }
            }
        } else {
            for win in snapshot.windows {
                let last = samples.last { $0.provider == snapshot.provider && $0.windowID == win.id }
                let changed = last == nil
                    || last?.remainingPercent != win.remainingPercent
                    || now.timeIntervalSince(last!.timestamp) >= 15 * 60
                if changed {
                    samples.append(QuotaHistoryPoint(
                        provider: snapshot.provider,
                        windowID: win.id,
                        windowTitle: win.title,
                        timestamp: now,
                        remainingPercent: win.remainingPercent,
                        resetsAt: win.resetsAt
                    ))
                    appended = true
                }
            }
        }

        if appended {
            pruneLocked(retention: retention, now: now)
            persistLocked()
        }
        return appended
    }

    public func applyRetention(_ retention: HistoryRetentionPolicy, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        pruneLocked(retention: retention, now: now)
        persistLocked()
    }

    public func clearAll() {
        lock.lock()
        samples.removeAll()
        persistLocked()
        lock.unlock()
    }

    public func populateDemoHistory(now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        var generated: [QuotaHistoryPoint] = []
        let start = now.addingTimeInterval(-7 * 86_400)
        let cycleEnd = now.addingTimeInterval(2 * 86_400)
        for step in 0...56 {
            let t = start.addingTimeInterval(Double(step) * 3 * 3600)
            guard t <= now else { break }
            let progress = Double(step) / 72.0
            let wave = sin(Double(step) * 0.45) * 3.0
            let rem = max(8, min(100, Int((100.0 - progress * 68.0 + wave).rounded())))
            for provider in [ProviderID.claude, .chatgpt, .antigravity] {
                let winID = provider == .antigravity ? "agy-gemini-weekly" : (provider == .chatgpt ? "codex-secondary" : "claude-current-week-all-models")
                generated.append(QuotaHistoryPoint(
                    provider: provider,
                    windowID: winID,
                    windowTitle: "每周配额",
                    timestamp: t,
                    remainingPercent: rem,
                    resetsAt: cycleEnd
                ))
            }
            generated.append(QuotaHistoryPoint(
                provider: .deepseek,
                windowID: "deepseek-cny",
                windowTitle: "API 余额 (CNY)",
                timestamp: t,
                balanceAmount: max(5.0, 50.0 - Double(step) * 0.24),
                currency: "CNY"
            ))
        }
        samples.append(contentsOf: generated)
        samples.sort { $0.timestamp < $1.timestamp }
        persistLocked()
    }

    public func exportCSV() -> Data {
        lock.lock()
        let copy = samples
        lock.unlock()

        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        iso.formatOptions = [.withInternetDateTime]

        var lines = ["unix_timestamp,local_iso8601,provider,window_id,window_title,remaining_percent,balance,currency"]
        for row in copy {
            let unix = Int(row.timestamp.timeIntervalSince1970)
            let local = iso.string(from: row.timestamp)
            let title = row.windowTitle.replacingOccurrences(of: "\"", with: "\"\"")
            let bal = row.balanceAmount.map { String(format: "%.2f", $0) } ?? ""
            let cur = row.currency ?? ""
            lines.append("\(unix),\(local),\(row.provider.rawValue),\"\(row.windowID)\",\"\(title)\",\(row.remainingPercent),\(bal),\(cur)")
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func pruneLocked(retention: HistoryRetentionPolicy, now: Date) {
        guard retention != .unlimited else { return }
        let cutoff = now.addingTimeInterval(-Double(retention.rawValue) * 86_400)
        samples.removeAll { $0.timestamp < cutoff }
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
