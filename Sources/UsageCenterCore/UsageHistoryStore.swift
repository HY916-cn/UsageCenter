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
        let normalizedReset: Date? = if let resetsAt, resetsAt.timeIntervalSince1970 > 946_684_800 {
            resetsAt
        } else {
            nil
        }
        self.id = id
        self.provider = provider
        self.windowID = windowID
        self.windowTitle = windowTitle
        self.durationMinutes = durationMinutes
        self.timestamp = timestamp
        self.remainingPercent = remainingPercent
        self.resetsAt = normalizedReset
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
        func validReset(_ d: Date?) -> Date? {
            guard let d, d.timeIntervalSince1970 > 946_684_800 else { return nil }
            return d
        }

        let durationSecs = Double(activeWindow?.durationMinutes ?? 10_080) * 60.0
        let activeValidReset = validReset(activeWindow?.resetsAt)
        let liveBalanceUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let liveQuotaUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!

        // MARK: Balance Series (DeepSeek)
        if isBalance {
            let interval: DateInterval = switch mode {
            case .currentCycle, .days7:
                DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
            case .days14:
                DateInterval(start: now.addingTimeInterval(-14 * 86_400), end: now)
            case .days30:
                DateInterval(start: now.addingTimeInterval(-30 * 86_400), end: now)
            case .browse:
                calendarUnit.interval(offset: calendarOffset, now: now)
            }

            var inRange = samples
                .filter { $0.timestamp >= interval.start && $0.timestamp <= interval.end }
                .sorted { $0.timestamp < $1.timestamp }

            if mode != .browse, let bal = liveBalance {
                let shouldAppend = inRange.last.map {
                    abs(($0.balanceAmount ?? -1) - bal) >= 0.001 || now.timeIntervalSince($0.timestamp) > 5
                } ?? true
                if shouldAppend {
                    inRange.append(QuotaHistoryPoint(
                        id: liveBalanceUUID,
                        provider: .deepseek,
                        windowID: "deepseek-live",
                        windowTitle: "当前余额",
                        timestamp: now,
                        balanceAmount: bal
                    ))
                }
            }

            guard !inRange.isEmpty else { return nil }

            var plotted: [QuotaChartSeries.PlottedPoint] = []
            for (idx, pt) in inRange.enumerated() {
                let val = pt.balanceAmount ?? 0
                if idx > 0 {
                    let prev = inRange[idx - 1]
                    let prevVal = prev.balanceAmount ?? 0
                    // Render top-up / recharge as a clean step-up at recharge timestamp instead of a long ramp
                    if val - prevVal >= 0.01 && pt.timestamp.timeIntervalSince(prev.timestamp) > 60 {
                        plotted.append(QuotaChartSeries.PlottedPoint(
                            id: "topup-step-\(pt.id.uuidString)",
                            cycleID: "balance",
                            date: pt.timestamp.addingTimeInterval(-1),
                            value: prevVal
                        ))
                    }
                }
                plotted.append(QuotaChartSeries.PlottedPoint(
                    id: pt.id.uuidString,
                    cycleID: "balance",
                    date: pt.timestamp,
                    value: val
                ))
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

        // MARK: Quota Series (Claude / ChatGPT / Antigravity)
        // 1. Sort all samples up to the query end, append live point, remove transient replica flaps,
        //    and segment into logical reset cycles BEFORE slicing by time range.
        let queryUpperBound: Date = switch mode {
        case .browse:
            calendarUnit.interval(offset: calendarOffset, now: now).end
        case .currentCycle:
            max(now, activeValidReset ?? now)
        case .days7, .days14, .days30:
            now
        }

        var allOrdered = samples
            .filter { $0.timestamp <= queryUpperBound }
            .sorted { $0.timestamp < $1.timestamp }

        if mode != .browse, let win = activeWindow {
            let shouldAppend = allOrdered.last.map {
                $0.remainingPercent != win.remainingPercent || now.timeIntervalSince($0.timestamp) > 5
            } ?? true
            if shouldAppend {
                allOrdered.append(QuotaHistoryPoint(
                    id: liveQuotaUUID,
                    provider: .chatgpt,
                    windowID: win.id,
                    windowTitle: win.title,
                    durationMinutes: win.durationMinutes,
                    timestamp: now,
                    remainingPercent: win.remainingPercent,
                    resetsAt: win.resetsAt
                ))
            }
        }

        let cleanedAll = removeTransientResetRegressions(from: allOrdered)
        let logicalCycles = segmentIntoLogicalCycles(cleanedAll)
        guard !logicalCycles.isEmpty else { return nil }

        func idealPercent(at date: Date, cycleStart: Date, cycleEnd: Date) -> Double {
            let span = cycleEnd.timeIntervalSince(cycleStart)
            guard span > 0 else { return 0 }
            return min(100, max(0, cycleEnd.timeIntervalSince(date) / span * 100.0))
        }

        // 2A. Current Cycle Mode — strictly display ONLY the latest logical cycle!
        if mode == .currentCycle {
            guard let currentCycle = logicalCycles.last, let firstSample = currentCycle.first else {
                return nil
            }
            let prevCycleEndTimestamp = logicalCycles.count >= 2 ? logicalCycles[logicalCycles.count - 2].last?.timestamp : nil
            let consumedReset = currentCycle.last(where: { $0.remainingPercent < 100 }).flatMap { validReset($0.resetsAt) }
            let cycleReset = activeValidReset ?? consumedReset ?? (firstSample.remainingPercent < 100 ? validReset(currentCycle.last?.resetsAt) : nil)
            let isStartedCycle = (cycleReset != nil && cycleReset! > firstSample.timestamp)

            let cycleStart: Date
            let cycleEnd: Date
            if let reset = cycleReset, reset > firstSample.timestamp {
                let nominalStart = reset.addingTimeInterval(-durationSecs)
                cycleStart = if let prevEnd = prevCycleEndTimestamp {
                    max(nominalStart, prevEnd.addingTimeInterval(1))
                } else {
                    nominalStart
                }
                cycleEnd = max(reset, now)
            } else {
                // Freshly reset 100% cycle whose countdown has not started yet (e.g. r == nil or unused 100%)
                if let prevEnd = prevCycleEndTimestamp {
                    let candidateStart = max(firstSample.timestamp, prevEnd.addingTimeInterval(1))
                    cycleStart = min(candidateStart, now.addingTimeInterval(-60))
                    cycleEnd = now
                } else {
                    cycleStart = min(firstSample.timestamp, now.addingTimeInterval(-3600))
                    cycleEnd = now
                }
            }

            let visibleSamples = currentCycle.filter { $0.timestamp >= cycleStart && $0.timestamp <= cycleEnd }
            guard !visibleSamples.isEmpty else { return nil }

            let cycID = "cycle-current"
            var plotted: [QuotaChartSeries.PlottedPoint] = []
            var gapDates: [Date] = []
            var hasGap = false

            if let firstVis = visibleSamples.first {
                if firstVis.timestamp > cycleStart.addingTimeInterval(1) {
                    plotted.append(QuotaChartSeries.PlottedPoint(
                        id: "synthetic-start-current",
                        cycleID: cycID,
                        date: cycleStart,
                        value: 100
                    ))
                    gapDates.append(cycleStart)
                    if firstVis.timestamp.timeIntervalSince(cycleStart) > 45 * 60 && firstVis.remainingPercent < 100 {
                        hasGap = true
                    }
                }
            }

            var minRem = 100
            for (idx, s) in visibleSamples.enumerated() {
                minRem = min(minRem, s.remainingPercent)
                if idx > 0, s.timestamp.timeIntervalSince(visibleSamples[idx - 1].timestamp) > 45 * 60 {
                    hasGap = true
                }
                plotted.append(QuotaChartSeries.PlottedPoint(
                    id: s.id.uuidString,
                    cycleID: cycID,
                    date: s.timestamp,
                    value: Double(s.remainingPercent)
                ))
            }

            if plotted.count == 1, let only = plotted.first {
                let anchor = max(cycleStart, only.date.addingTimeInterval(-60))
                if only.date > anchor {
                    plotted.insert(QuotaChartSeries.PlottedPoint(
                        id: "synthetic-current-anchor",
                        cycleID: cycID,
                        date: anchor,
                        value: only.value
                    ), at: 0)
                }
            }

            var ideals: [QuotaChartSeries.IdealSegment] = []
            if isStartedCycle, let reset = cycleReset, reset > cycleStart {
                ideals.append(QuotaChartSeries.IdealSegment(
                    id: "ideal-current",
                    start: cycleStart,
                    end: reset,
                    startValue: 100,
                    endValue: 0
                ))
            }

            var projectedRem: Int?
            var projectedZero: Date?
            if isStartedCycle,
               let last = visibleSamples.last,
               let reset = cycleReset,
               reset > now {
                let nominalStart = reset.addingTimeInterval(-durationSecs)
                let elapsed = now.timeIntervalSince(nominalStart)
                let consumed = Double(100 - last.remainingPercent)
                if elapsed > 1800, consumed > 0 {
                    let ratePerSec = consumed / elapsed
                    let totalProjectedConsumed = ratePerSec * durationSecs
                    projectedRem = max(0, min(100, Int((100.0 - totalProjectedConsumed).rounded())))
                    if totalProjectedConsumed > 100.0 {
                        projectedZero = now.addingTimeInterval(Double(last.remainingPercent) / ratePerSec)
                    }
                } else if consumed == 0 {
                    projectedRem = 100
                }
            }

            gapDates.append(contentsOf: visibleSamples.map(\.timestamp))
            let gaps = computeGaps(dates: gapDates)
            return QuotaChartSeries(
                domain: cycleStart...max(cycleEnd, plotted.last?.date ?? cycleEnd),
                points: plotted,
                idealSegments: ideals,
                gaps: gaps,
                observedConsumedPercent: max(0, 100 - minRem),
                isLowerBoundConsumption: hasGap || !gaps.isEmpty,
                projectedRemainingAtReset: projectedRem,
                projectedExhaustionDate: projectedZero,
                isBalanceSeries: false
            )
        }

        // 2B. Multi-Cycle Historical Modes (days7 / days14 / days30 / browse)
        let interval: DateInterval = switch mode {
        case .currentCycle, .days7:
            DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
        case .days14:
            DateInterval(start: now.addingTimeInterval(-14 * 86_400), end: now)
        case .days30:
            DateInterval(start: now.addingTimeInterval(-30 * 86_400), end: now)
        case .browse:
            calendarUnit.interval(offset: calendarOffset, now: now)
        }

        var plotted: [QuotaChartSeries.PlottedPoint] = []
        var ideals: [QuotaChartSeries.IdealSegment] = []
        var observedDatesInInterval: [Date] = []
        var totalConsumed = 0
        var isLowerBound = false

        for (idx, cycle) in logicalCycles.enumerated() {
            let inWindow = cycle.filter { $0.timestamp >= interval.start && $0.timestamp <= interval.end }
            guard let firstVis = inWindow.first, let lastVis = inWindow.last else { continue }

            let cycID = "cycle-\(idx)"
            let prevCycleLastTime = idx > 0 ? logicalCycles[idx - 1].last?.timestamp : nil
            let nextCycleFirstTime = idx + 1 < logicalCycles.count ? logicalCycles[idx + 1].first?.timestamp : nil

            let isLatest = (idx == logicalCycles.count - 1)
            let consumedReset = cycle.last(where: { $0.remainingPercent < 100 }).flatMap { validReset($0.resetsAt) }
            let cycleEndReset = (isLatest && mode != .browse)
                ? (activeValidReset ?? consumedReset)
                : consumedReset

            let nominalStart = cycleEndReset.map { $0.addingTimeInterval(-durationSecs) }
            var cycVisibleStart = max(interval.start, nominalStart ?? firstVis.timestamp)
            if let prevEnd = prevCycleLastTime {
                cycVisibleStart = max(cycVisibleStart, prevEnd.addingTimeInterval(1))
            }
            cycVisibleStart = min(cycVisibleStart, firstVis.timestamp)

            var cycVisibleEnd = min(interval.end, cycleEndReset ?? lastVis.timestamp)
            if let nextStart = nextCycleFirstTime {
                cycVisibleEnd = min(cycVisibleEnd, nextStart.addingTimeInterval(-1))
            }
            cycVisibleEnd = max(cycVisibleEnd, lastVis.timestamp)

            // Add clean 100% reset anchor if this cycle began inside [interval.start, firstVis.timestamp]
            let cycleBeganAfterPrevious = (idx > 0 && cycle.first?.id == firstVis.id)
            let cycleBeganInsideRange = nominalStart.map { $0 >= interval.start } ?? false
            if (cycleBeganAfterPrevious || cycleBeganInsideRange),
               firstVis.timestamp > cycVisibleStart.addingTimeInterval(1) {
                plotted.append(QuotaChartSeries.PlottedPoint(
                    id: "synthetic-hist-\(idx)",
                    cycleID: cycID,
                    date: cycVisibleStart,
                    value: 100
                ))
            } else if !cycleBeganAfterPrevious && !cycleBeganInsideRange && firstVis.remainingPercent < 100 {
                isLowerBound = true
            }

            let baseline = (cycleBeganAfterPrevious || cycleBeganInsideRange) ? 100 : firstVis.remainingPercent
            var lowestInCycle = baseline
            for (sIdx, s) in inWindow.enumerated() {
                lowestInCycle = min(lowestInCycle, s.remainingPercent)
                if sIdx > 0, s.timestamp.timeIntervalSince(inWindow[sIdx - 1].timestamp) > 45 * 60 {
                    isLowerBound = true
                }
                plotted.append(QuotaChartSeries.PlottedPoint(
                    id: s.id.uuidString,
                    cycleID: cycID,
                    date: s.timestamp,
                    value: Double(s.remainingPercent)
                ))
                observedDatesInInterval.append(s.timestamp)
            }
            totalConsumed += max(0, baseline - lowestInCycle)

            // Ensure a brand-new 1-sample cycle right after reset still renders a short visible segment
            let cycPointsCount = plotted.filter { $0.cycleID == cycID }.count
            if cycPointsCount == 1, let onlyPt = plotted.last {
                let anchor = max(interval.start, prevCycleLastTime?.addingTimeInterval(1) ?? onlyPt.date.addingTimeInterval(-60), onlyPt.date.addingTimeInterval(-60))
                if onlyPt.date > anchor {
                    plotted.insert(QuotaChartSeries.PlottedPoint(
                        id: "synthetic-single-\(idx)",
                        cycleID: cycID,
                        date: anchor,
                        value: onlyPt.value
                    ), at: plotted.count - 1)
                }
            }

            if let reset = cycleEndReset,
               let nomStart = nominalStart,
               cycle.contains(where: { $0.remainingPercent < 100 }),
               cycVisibleEnd > cycVisibleStart {
                ideals.append(QuotaChartSeries.IdealSegment(
                    id: "ideal-hist-\(idx)",
                    start: cycVisibleStart,
                    end: cycVisibleEnd,
                    startValue: idealPercent(at: cycVisibleStart, cycleStart: nomStart, cycleEnd: reset),
                    endValue: idealPercent(at: cycVisibleEnd, cycleStart: nomStart, cycleEnd: reset)
                ))
            }
        }

        guard !plotted.isEmpty else { return nil }

        let gaps = computeGaps(dates: observedDatesInInterval.sorted())
        return QuotaChartSeries(
            domain: interval.start...interval.end,
            points: plotted,
            idealSegments: ideals,
            gaps: gaps,
            observedConsumedPercent: totalConsumed,
            isLowerBoundConsumption: isLowerBound || !gaps.isEmpty,
            projectedRemainingAtReset: nil,
            projectedExhaustionDate: nil,
            isBalanceSeries: false
        )
    }

    /// Removes short-lived stale-replica regressions (e.g. 100% r=new -> 53% r=old -> 100% r=new)
    /// that occur on distributed backends during the first few minutes after a quota reset.
    private static func removeTransientResetRegressions(from samples: [QuotaHistoryPoint]) -> [QuotaHistoryPoint] {
        guard samples.count >= 3 else { return samples }
        let resetTol: TimeInterval = 1800
        let flapWindow: TimeInterval = 3 * 3600

        var filtered: [QuotaHistoryPoint] = []
        var i = 0
        while i < samples.count {
            let cand = samples[i]
            guard let stable = filtered.last else {
                filtered.append(cand)
                i += 1
                continue
            }

            // Detect sudden drop in remaining% accompanied by reset date jumping backward (or from nil/new back to old)
            let resetRegressed: Bool = {
                if let sr = stable.resetsAt, let cr = cand.resetsAt {
                    return cr.timeIntervalSince(sr) < -resetTol
                }
                return false
            }()

            guard resetRegressed && (stable.remainingPercent - cand.remainingPercent >= 3) else {
                filtered.append(cand)
                i += 1
                continue
            }

            var cursor = i + 1
            var returnedToStable = false
            while cursor < samples.count,
                  samples[cursor].timestamp.timeIntervalSince(cand.timestamp) <= flapWindow {
                let probe = samples[cursor]
                if let sr = stable.resetsAt, let pr = probe.resetsAt,
                   abs(pr.timeIntervalSince(sr)) <= resetTol || pr > sr {
                    returnedToStable = true
                    break
                }
                cursor += 1
            }

            if returnedToStable {
                i = cursor // Skip transient lagging-replica samples
            } else {
                filtered.append(cand)
                i += 1
            }
        }
        return filtered
    }

    private static func segmentIntoLogicalCycles(_ samples: [QuotaHistoryPoint]) -> [[QuotaHistoryPoint]] {
        guard let first = samples.first else { return [] }
        var result: [[QuotaHistoryPoint]] = []
        var current: [QuotaHistoryPoint] = [first]

        for sample in samples.dropFirst() {
            guard let prev = current.last else { continue }
            let jumpedUp = (sample.remainingPercent - prev.remainingPercent >= 3)
            let resetAdvanced: Bool = {
                guard prev.remainingPercent < 100 else { return false }
                guard let r1 = prev.resetsAt, let r2 = sample.resetsAt else { return false }
                return r2.timeIntervalSince(r1) > 1800
            }()

            if jumpedUp || resetAdvanced {
                result.append(current)
                current = [sample]
            } else {
                current.append(sample)
            }
        }
        result.append(current)
        return result
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

    public static func tokenCalendarComponent(for range: TokenHistoryRange) -> Calendar.Component {
        switch range {
        case .days7, .days30, .days90: return .day
        case .year1: return .weekOfYear
        case .all: return .month
        }
    }

    public static func tokenDomain(
        for range: TokenHistoryRange,
        bars: [AggregatedTokenBar],
        now: Date = Date()
    ) -> ClosedRange<Date> {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        switch range {
        case .days7:
            let start = cal.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
            let end = cal.date(byAdding: .day, value: 1, to: todayStart) ?? now
            return start...end
        case .days30:
            let start = cal.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
            let end = cal.date(byAdding: .day, value: 1, to: todayStart) ?? now
            return start...end
        case .days90:
            let start = cal.date(byAdding: .day, value: -89, to: todayStart) ?? todayStart
            let end = cal.date(byAdding: .day, value: 1, to: todayStart) ?? now
            return start...end
        case .year1:
            let curWeek = cal.dateInterval(of: .weekOfYear, for: todayStart)?.start ?? todayStart
            let start = cal.date(byAdding: .weekOfYear, value: -51, to: curWeek) ?? curWeek
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: curWeek) ?? now
            return start...end
        case .all:
            let curMonth = cal.dateInterval(of: .month, for: todayStart)?.start ?? todayStart
            let minSixMonths = cal.date(byAdding: .month, value: -5, to: curMonth) ?? curMonth
            let earliestBar = bars.first.flatMap { cal.dateInterval(of: .month, for: $0.bucketDate)?.start }
            let start = earliestBar.map { min($0, minSixMonths) } ?? minSixMonths
            let end = cal.date(byAdding: .month, value: 1, to: curMonth) ?? now
            return start...end
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
