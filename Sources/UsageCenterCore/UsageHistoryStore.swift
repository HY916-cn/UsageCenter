import Foundation

public struct QuotaHistoryPoint: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let provider: ProviderID
    public let windowID: String
    public let windowTitle: String
    public let durationMinutes: Int?
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
        durationMinutes: Int? = nil,
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
        self.durationMinutes = durationMinutes
        self.timestamp = timestamp
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.balanceAmount = balanceAmount
        self.currency = currency
    }
}

public enum HistoryQueryMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case currentCycle
    case days7
    case days14
    case days30
    case browse

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .currentCycle: return "当前周期"
        case .days7: return "近 7 天"
        case .days14: return "近 14 天"
        case .days30: return "近 30 天"
        case .browse: return "浏览日历"
        }
    }
}

public enum HistoryCalendarUnit: String, CaseIterable, Codable, Identifiable, Sendable {
    case week
    case month

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .week: return "按周"
        case .month: return "按月"
        }
    }

    public func interval(offset: Int, now: Date = Date()) -> DateInterval {
        let cal = Calendar.current
        let comp: Calendar.Component = (self == .week) ? .weekOfYear : .month
        let base = cal.dateInterval(of: comp, for: now) ?? DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
        let start = cal.date(byAdding: comp, value: offset, to: base.start) ?? base.start
        let end = cal.date(byAdding: comp, value: 1, to: start) ?? start.addingTimeInterval(7 * 86_400)
        return DateInterval(start: start, end: end)
    }
}

public enum TokenHistoryRange: String, CaseIterable, Codable, Identifiable, Sendable {
    case days7
    case days30
    case days90
    case year1
    case all

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .days7: return "7 天"
        case .days30: return "30 天"
        case .days90: return "90 天"
        case .year1: return "1 年"
        case .all: return "全部"
        }
    }
}

public struct AggregatedTokenBar: Identifiable, Equatable, Sendable {
    public var id: Date { bucketDate }
    public let bucketDate: Date
    public let label: String
    public let tokens: Int64
}

public struct QuotaChartSeries: Equatable, Sendable {
    public struct PlottedPoint: Identifiable, Equatable, Sendable {
        public let id: String
        public let cycleID: String
        public let date: Date
        public let value: Double
    }

    public struct IdealSegment: Identifiable, Equatable, Sendable {
        public let id: String
        public let start: Date
        public let end: Date
        public let startValue: Double
        public let endValue: Double
    }

    public struct UnrecordedGap: Identifiable, Equatable, Sendable {
        public let id: String
        public let start: Date
        public let end: Date
    }

    public let domain: ClosedRange<Date>
    public let points: [PlottedPoint]
    public let idealSegments: [IdealSegment]
    public let gaps: [UnrecordedGap]
    public let observedConsumedPercent: Int
    public let isLowerBoundConsumption: Bool
    public let projectedRemainingAtReset: Int?
    public let projectedExhaustionDate: Date?
    public let isBalanceSeries: Bool
}

// MARK: - CodexMeter-Aligned History Analytics Builder

public enum HistoryAnalytics {
    public static func buildQuotaSeries(
        samples: [QuotaHistoryPoint],
        mode: HistoryQueryMode,
        calendarUnit: HistoryCalendarUnit,
        calendarOffset: Int,
        activeWindow: QuotaWindow?,
        isBalance: Bool,
        liveBalance: Double? = nil,
        now: Date = Date()
    ) -> QuotaChartSeries? {
        let interval: DateInterval
        let durationSecs = Double(activeWindow?.durationMinutes ?? 10_080) * 60.0

        switch mode {
        case .currentCycle:
            if !isBalance, let reset = activeWindow?.resetsAt, reset > now {
                let start = reset.addingTimeInterval(-durationSecs)
                interval = DateInterval(start: start, end: reset)
            } else if !isBalance {
                interval = DateInterval(start: now.addingTimeInterval(-durationSecs), end: now)
            } else {
                interval = DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
            }
        case .days7:
            interval = DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
        case .days14:
            interval = DateInterval(start: now.addingTimeInterval(-14 * 86_400), end: now)
        case .days30:
            interval = DateInterval(start: now.addingTimeInterval(-30 * 86_400), end: now)
        case .browse:
            interval = calendarUnit.interval(offset: calendarOffset, now: now)
        }

        var inRange = samples
            .filter { $0.timestamp >= interval.start && $0.timestamp <= interval.end }
            .sorted { $0.timestamp < $1.timestamp }

        // Ensure current live state is always represented so inline history charts render immediately
        if mode != .browse {
            if isBalance, let bal = liveBalance {
                let shouldAppend = inRange.last.map {
                    abs(($0.balanceAmount ?? -1) - bal) >= 0.001 || now.timeIntervalSince($0.timestamp) > 5
                } ?? true
                if shouldAppend {
                    inRange.append(QuotaHistoryPoint(
                        provider: .deepseek,
                        windowID: "deepseek-live",
                        windowTitle: "当前余额",
                        timestamp: now,
                        balanceAmount: bal
                    ))
                }
            } else if !isBalance, let win = activeWindow {
                let sampleTime = min(now, interval.end)
                if sampleTime >= interval.start {
                    let shouldAppend = inRange.last.map {
                        $0.remainingPercent != win.remainingPercent || sampleTime.timeIntervalSince($0.timestamp) > 5
                    } ?? true
                    if shouldAppend {
                        inRange.append(QuotaHistoryPoint(
                            provider: .chatgpt,
                            windowID: win.id,
                            windowTitle: win.title,
                            durationMinutes: win.durationMinutes,
                            timestamp: sampleTime,
                            remainingPercent: win.remainingPercent,
                            resetsAt: win.resetsAt
                        ))
                    }
                }
            }
        }

        guard !inRange.isEmpty else { return nil }

        if isBalance {
            var plotted = inRange.map {
                QuotaChartSeries.PlottedPoint(
                    id: $0.id.uuidString,
                    cycleID: "balance",
                    date: $0.timestamp,
                    value: $0.balanceAmount ?? 0
                )
            }
            if plotted.count == 1, let only = plotted.first {
                let anchorDate = max(interval.start, only.date.addingTimeInterval(-24 * 3600))
                if only.date > anchorDate {
                    plotted.insert(QuotaChartSeries.PlottedPoint(
                        id: "balance-baseline",
                        cycleID: "balance",
                        date: anchorDate,
                        value: only.value
                    ), at: 0)
                }
            }
            return QuotaChartSeries(
                domain: interval.start...max(interval.end, plotted.last?.date ?? interval.end),
                points: plotted,
                idealSegments: [],
                gaps: computeGaps(dates: inRange.map(\.timestamp)),
                observedConsumedPercent: 0,
                isLowerBoundConsumption: false,
                projectedRemainingAtReset: nil,
                projectedExhaustionDate: nil,
                isBalanceSeries: true
            )
        }

        // Split into distinct quota reset cycles when remaining% jumps up by >=5% or resetsAt shifts >10m
        var cycleIndex = 0
        var plotted: [QuotaChartSeries.PlottedPoint] = []
        var ideals: [QuotaChartSeries.IdealSegment] = []
        var observedDrop = 0
        var hasGap = false
        var gapDates: [Date] = []

        // Every active quota cycle begins at 100% at cycleStart (resetsAt - duration)
        if mode == .currentCycle, let first = inRange.first {
            if first.timestamp > interval.start.addingTimeInterval(1) {
                plotted.append(QuotaChartSeries.PlottedPoint(
                    id: "synthetic-start-0",
                    cycleID: "cycle-0",
                    date: interval.start,
                    value: 100
                ))
                gapDates.append(interval.start)
                if first.timestamp.timeIntervalSince(interval.start) > 45 * 60 && first.remainingPercent < 100 {
                    hasGap = true
                }
            }
            observedDrop += max(0, 100 - first.remainingPercent)
            ideals.append(QuotaChartSeries.IdealSegment(
                id: "ideal-0",
                start: interval.start,
                end: interval.end,
                startValue: 100,
                endValue: 0
            ))
        } else if plotted.isEmpty, inRange.count == 1, let only = inRange.first {
            let anchorDate = max(interval.start, only.timestamp.addingTimeInterval(-min(durationSecs, 6 * 3600)))
            if only.timestamp > anchorDate {
                plotted.append(QuotaChartSeries.PlottedPoint(
                    id: "synthetic-single-anchor",
                    cycleID: "cycle-0",
                    date: anchorDate,
                    value: Double(only.remainingPercent)
                ))
            }
        }

        for (i, sample) in inRange.enumerated() {
            if i > 0 {
                let prev = inRange[i - 1]
                let resetAdvanced: Bool = {
                    guard let r1 = prev.resetsAt, let r2 = sample.resetsAt else { return false }
                    return r2.timeIntervalSince(r1) > 600
                }()
                let jumpedUp = sample.remainingPercent - prev.remainingPercent >= 5

                if resetAdvanced || jumpedUp {
                    cycleIndex += 1
                    let cycID = "cycle-\(cycleIndex)"
                    if let r2 = sample.resetsAt {
                        let cStart = max(interval.start, r2.addingTimeInterval(-durationSecs))
                        plotted.append(QuotaChartSeries.PlottedPoint(
                            id: "synthetic-\(cycleIndex)",
                            cycleID: cycID,
                            date: cStart,
                            value: 100
                        ))
                        ideals.append(QuotaChartSeries.IdealSegment(
                            id: "ideal-\(cycleIndex)",
                            start: cStart,
                            end: min(interval.end, r2),
                            startValue: 100,
                            endValue: 0
                        ))
                        observedDrop += max(0, 100 - sample.remainingPercent)
                    }
                } else {
                    if sample.timestamp.timeIntervalSince(prev.timestamp) > 45 * 60 {
                        hasGap = true
                    }
                    let drop = prev.remainingPercent - sample.remainingPercent
                    if drop > 0 {
                        observedDrop += drop
                    }
                }
            }

            plotted.append(QuotaChartSeries.PlottedPoint(
                id: sample.id.uuidString,
                cycleID: "cycle-\(cycleIndex)",
                date: sample.timestamp,
                value: Double(sample.remainingPercent)
            ))
        }

        if mode != .currentCycle, ideals.isEmpty, let first = inRange.first, let reset = first.resetsAt {
            let cStart = max(interval.start, reset.addingTimeInterval(-durationSecs))
            ideals.append(QuotaChartSeries.IdealSegment(
                id: "ideal-base",
                start: cStart,
                end: min(interval.end, reset),
                startValue: 100,
                endValue: 0
            ))
        }

        // Burn-rate projection for current cycle
        var projectedRem: Int?
        var projectedZero: Date?
        if mode == .currentCycle,
           let last = inRange.last,
           let reset = activeWindow?.resetsAt ?? last.resetsAt,
           reset > now {
            let cycleStart = reset.addingTimeInterval(-durationSecs)
            let elapsed = now.timeIntervalSince(cycleStart)
            let consumed = Double(100 - last.remainingPercent)
            if elapsed > 1800, consumed > 0 {
                let ratePerSec = consumed / elapsed
                let totalProjectedConsumed = ratePerSec * durationSecs
                let remAtEnd = Int((100.0 - totalProjectedConsumed).rounded())
                projectedRem = max(0, min(100, remAtEnd))
                if totalProjectedConsumed > 100.0 {
                    let secsToZero = Double(last.remainingPercent) / ratePerSec
                    projectedZero = now.addingTimeInterval(secsToZero)
                }
            } else if consumed == 0 {
                projectedRem = 100
            }
        }

        gapDates.append(contentsOf: inRange.map(\.timestamp))
        let gaps = computeGaps(dates: gapDates)
        return QuotaChartSeries(
            domain: interval.start...interval.end,
            points: plotted,
            idealSegments: ideals,
            gaps: gaps,
            observedConsumedPercent: observedDrop,
            isLowerBoundConsumption: hasGap || !gaps.isEmpty,
            projectedRemainingAtReset: projectedRem,
            projectedExhaustionDate: projectedZero,
            isBalanceSeries: false
        )
    }

    private static func computeGaps(dates: [Date]) -> [QuotaChartSeries.UnrecordedGap] {
        guard dates.count >= 2 else { return [] }
        var result: [QuotaChartSeries.UnrecordedGap] = []
        for i in 1..<dates.count {
            let gapSecs = dates[i].timeIntervalSince(dates[i - 1])
            if gapSecs >= 2 * 3600 {
                result.append(QuotaChartSeries.UnrecordedGap(
                    id: "gap-\(i)",
                    start: dates[i - 1],
                    end: dates[i]
                ))
            }
        }
        return result
    }

    public static func aggregateTokens(
        dailyBuckets: [TokenDailyPoint],
        range: TokenHistoryRange,
        now: Date = Date()
    ) -> [AggregatedTokenBar] {
        let cal = Calendar.current
        let parsed: [(Date, Int64)] = dailyBuckets.compactMap { row in
            guard let d = row.parsedDate else { return nil }
            return (d, row.tokens)
        }.sorted { $0.0 < $1.0 }

        guard !parsed.isEmpty else { return [] }

        let cutoff: Date? = switch range {
        case .days7: now.addingTimeInterval(-7 * 86_400)
        case .days30: now.addingTimeInterval(-30 * 86_400)
        case .days90: now.addingTimeInterval(-90 * 86_400)
        case .year1: now.addingTimeInterval(-365 * 86_400)
        case .all: nil
        }

        let filtered = parsed.filter { cutoff == nil || $0.0 >= cutoff! }
        guard !filtered.isEmpty else { return [] }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "zh_CN")
        dayFormatter.dateFormat = "MM-dd"

        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "zh_CN")
        monthFormatter.dateFormat = "yyyy-MM"

        switch range {
        case .days7, .days30, .days90:
            return filtered.map { d, tok in
                AggregatedTokenBar(bucketDate: d, label: dayFormatter.string(from: d), tokens: tok)
            }
        case .year1:
            var byWeek: [Date: Int64] = [:]
            for (d, tok) in filtered {
                let wStart = cal.dateInterval(of: .weekOfYear, for: d)?.start ?? d
                byWeek[wStart, default: 0] += tok
            }
            return byWeek.keys.sorted().map { w in
                AggregatedTokenBar(bucketDate: w, label: "\(dayFormatter.string(from: w))周", tokens: byWeek[w] ?? 0)
            }
        case .all:
            var byMonth: [Date: Int64] = [:]
            for (d, tok) in filtered {
                let mStart = cal.dateInterval(of: .month, for: d)?.start ?? d
                byMonth[mStart, default: 0] += tok
            }
            return byMonth.keys.sorted().map { m in
                AggregatedTokenBar(bucketDate: m, label: monthFormatter.string(from: m), tokens: byMonth[m] ?? 0)
            }
        }
    }
}

// MARK: - Persistent History Store (Quota + Accumulated Daily Tokens)

private struct PersistedHistoryArchive: Codable {
    var samples: [QuotaHistoryPoint]
    var dailyTokens: [String: Int64]
    var lifetimeTokens: Int64?
    var peakDailyTokens: Int64?
    var currentStreakDays: Int64?
}

public final class UsageHistoryStore: @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL
    private var archive = PersistedHistoryArchive(samples: [], dailyTokens: [:])

    public static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("UsageCenter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage_history_v2.json")
    }

    public init(fileURL: URL = UsageHistoryStore.defaultStorageURL()) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL) {
            if let decoded = try? JSONDecoder().decode(PersistedHistoryArchive.self, from: data) {
                self.archive = decoded
            } else if let legacy = try? JSONDecoder().decode([QuotaHistoryPoint].self, from: data) {
                self.archive.samples = legacy
            }
        }
    }

    public func allSamples() -> [QuotaHistoryPoint] {
        lock.lock()
        defer { lock.unlock() }
        return archive.samples
    }

    public func storedTokenActivity() -> TokenActivitySnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard !archive.dailyTokens.isEmpty || archive.lifetimeTokens != nil else { return nil }
        let buckets = archive.dailyTokens.keys.sorted().map {
            TokenDailyPoint(startDate: $0, tokens: archive.dailyTokens[$0] ?? 0)
        }
        return TokenActivitySnapshot(
            dailyBuckets: buckets,
            lifetimeTokens: archive.lifetimeTokens,
            peakDailyTokens: archive.peakDailyTokens,
            currentStreakDays: archive.currentStreakDays
        )
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

        var dirty = false

        if let tok = snapshot.tokenActivity {
            for b in tok.dailyBuckets where archive.dailyTokens[b.startDate] != b.tokens {
                archive.dailyTokens[b.startDate] = b.tokens
                dirty = true
            }
            if let lt = tok.lifetimeTokens, archive.lifetimeTokens != lt {
                archive.lifetimeTokens = lt
                dirty = true
            }
            if let pk = tok.peakDailyTokens, archive.peakDailyTokens != pk {
                archive.peakDailyTokens = pk
                dirty = true
            }
            if let st = tok.currentStreakDays, archive.currentStreakDays != st {
                archive.currentStreakDays = st
                dirty = true
            }
        }

        if snapshot.provider == .deepseek {
            if let bal = snapshot.balances.first {
                let winID = "deepseek-\(bal.currency.lowercased())"
                let last = archive.samples.last { $0.provider == .deepseek && $0.windowID == winID }
                let changed = last == nil
                    || abs((last?.balanceAmount ?? -1) - bal.numericTotal) >= 0.005
                    || now.timeIntervalSince(last!.timestamp) >= 15 * 60
                if changed {
                    archive.samples.append(QuotaHistoryPoint(
                        provider: .deepseek,
                        windowID: winID,
                        windowTitle: "可用余额 (\(bal.currency))",
                        timestamp: now,
                        balanceAmount: bal.numericTotal,
                        currency: bal.currency
                    ))
                    dirty = true
                }
            }
        } else {
            for win in snapshot.windows {
                let last = archive.samples.last { $0.provider == snapshot.provider && $0.windowID == win.id }
                let changed = last == nil
                    || last?.remainingPercent != win.remainingPercent
                    || now.timeIntervalSince(last!.timestamp) >= 15 * 60
                if changed {
                    archive.samples.append(QuotaHistoryPoint(
                        provider: snapshot.provider,
                        windowID: win.id,
                        windowTitle: win.groupName.map { "\($0) · \(win.title)" } ?? win.title,
                        durationMinutes: win.durationMinutes,
                        timestamp: now,
                        remainingPercent: win.remainingPercent,
                        resetsAt: win.resetsAt
                    ))
                    dirty = true
                }
            }
        }

        if dirty {
            pruneLocked(retention: retention, now: now)
            persistLocked()
        }
        return dirty
    }

    public func applyRetention(_ retention: HistoryRetentionPolicy, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        pruneLocked(retention: retention, now: now)
        persistLocked()
    }

    public func clearAll() {
        lock.lock()
        archive = PersistedHistoryArchive(samples: [], dailyTokens: [:])
        persistLocked()
        lock.unlock()
    }

    public func populateDemoHistory(now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }

        let start = now.addingTimeInterval(-14 * 86_400)
        let cycle1Reset = now.addingTimeInterval(-5 * 86_400)
        let cycle2Reset = now.addingTimeInterval(2 * 86_400)

        for step in 0...112 {
            let t = start.addingTimeInterval(Double(step) * 3 * 3600)
            guard t <= now else { break }
            let isSecondCycle = t >= cycle1Reset
            let cStart = isSecondCycle ? cycle1Reset : cycle1Reset.addingTimeInterval(-7 * 86_400)
            let cReset = isSecondCycle ? cycle2Reset : cycle1Reset
            let frac = min(1.0, max(0.0, t.timeIntervalSince(cStart) / (7 * 86_400)))
            let rem = max(6, min(100, Int((100.0 - frac * 78.0 + sin(Double(step) * 0.5) * 2.5).rounded())))

            for (p, wid) in [(ProviderID.claude, "claude-current-week-all-models"),
                             (.chatgpt, "codex-secondary"),
                             (.antigravity, "agy-gemini-weekly")] {
                archive.samples.append(QuotaHistoryPoint(
                    provider: p,
                    windowID: wid,
                    windowTitle: "每周配额",
                    durationMinutes: 10_080,
                    timestamp: t,
                    remainingPercent: rem,
                    resetsAt: cReset
                ))
            }
            archive.samples.append(QuotaHistoryPoint(
                provider: .deepseek,
                windowID: "deepseek-cny",
                windowTitle: "可用余额 (CNY)",
                timestamp: t,
                balanceAmount: max(5.0, 58.0 - Double(step) * 0.19),
                currency: "CNY"
            ))
        }
        archive.samples.sort { $0.timestamp < $1.timestamp }
        persistLocked()
    }

    public func exportCSV() -> Data {
        lock.lock()
        let copy = archive.samples
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
        archive.samples.removeAll { $0.timestamp < cutoff }
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(archive) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
