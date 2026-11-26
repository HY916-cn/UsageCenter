import Foundation

public enum CLIParserError: LocalizedError, Equatable {
    case emptyOutput
    case unauthenticated(String)
    case invalidFormat(String)

    public var errorDescription: String? {
        switch self {
        case .emptyOutput:
            return "CLI 未返回有效输出"
        case .unauthenticated(let msg):
            return msg
        case .invalidFormat(let msg):
            return msg
        }
    }
}

public enum ANSIStripper {
    public static func strip(_ raw: String) -> String {
        var text = raw
        if let csi = try? NSRegularExpression(pattern: #"\x1B\[[0-9;?]*[A-Za-z]"#) {
            text = csi.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        if let osc = try? NSRegularExpression(pattern: #"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)"#) {
            text = osc.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

// MARK: - DSH Local Credential Reader (~/.dsh/.credentials.yaml)

public enum DSHCredentialReader {
    public struct DSHGrant: Equatable, Sendable {
        public let token: String
        public let issuer: String
    }

    public static func readDefaultGrant(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> DSHGrant? {
        let credURL = homeDirectory.appendingPathComponent(".dsh/.credentials.yaml")
        guard let content = try? String(contentsOf: credURL, encoding: .utf8) else {
            return nil
        }
        return parseYAMLGrant(content)
    }

    public static func parseYAMLGrant(_ yaml: String) -> DSHGrant? {
        let lines = yaml.components(separatedBy: .newlines)
        var inPlatformSection = false
        var platformIndent = -1
        var token: String?
        var issuer = "https://platform.deepseek.com"

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = rawLine.prefix { $0 == " " }.count

            if trimmed.hasPrefix("deepseek-account-platform/default:") {
                inPlatformSection = true
                platformIndent = indent
                continue
            }

            if inPlatformSection {
                if indent <= platformIndent {
                    break
                }
                if trimmed.hasPrefix("token:") {
                    let val = trimmed.dropFirst("token:".count)
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !val.isEmpty {
                        token = val
                    }
                } else if trimmed.hasPrefix("issuer:") {
                    let val = trimmed.dropFirst("issuer:".count)
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if val.hasPrefix("https://") {
                        issuer = val.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    }
                }
            }
        }

        guard let token, !token.isEmpty else { return nil }
        return DSHGrant(token: token, issuer: issuer)
    }
}

// MARK: - Claude CLI Parser

public enum ClaudeCLIParser {
    public struct AuthInfo: Equatable, Sendable {
        public let loggedIn: Bool
        public let subscriptionType: String?
        public let authMethod: String?
    }

    public static func parseAuthStatus(_ data: Data) -> AuthInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let loggedIn = (object["loggedIn"] as? Bool) ?? false
        let sub = object["subscriptionType"] as? String
        let method = object["authMethod"] as? String
        return AuthInfo(loggedIn: loggedIn, subscriptionType: sub, authMethod: method)
    }

    public static func parseUsageOutput(
        _ rawData: Data,
        authInfo: AuthInfo? = nil,
        referenceDate: Date = Date()
    ) throws -> ProviderSnapshot {
        let rawText = String(data: rawData, encoding: .utf8) ?? ""
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIParserError.emptyOutput
        }

        var contentText = rawText
        if let jsonObj = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
            if let isError = jsonObj["is_error"] as? Bool, isError,
               let resultText = jsonObj["result"] as? String {
                throw CLIParserError.invalidFormat(ANSIStripper.strip(resultText).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if let resultText = jsonObj["result"] as? String {
                contentText = resultText
            }
        }

        let clean = ANSIStripper.strip(contentText)
        if clean.localizedCaseInsensitiveContains("not logged in")
            || clean.localizedCaseInsensitiveContains("please run /login") {
            throw CLIParserError.unauthenticated("Claude CLI 未登录，请先在终端执行 claude login")
        }

        let windows = parseWindows(from: clean, referenceDate: referenceDate)
        guard !windows.isEmpty else {
            throw CLIParserError.invalidFormat("未能从 Claude CLI 解析出 5小时/周配额窗口")
        }

        let label: String
        if let sub = authInfo?.subscriptionType, !sub.isEmpty {
            label = "Claude \(sub.capitalized)"
        } else {
            label = "Claude Subscription"
        }

        return ProviderSnapshot(
            provider: .claude,
            accountLabel: label,
            windows: windows,
            updatedAt: referenceDate
        )
    }

    private static func parseWindows(from text: String, referenceDate: Date) -> [QuotaWindow] {
        let pattern = #"^([^\n:]+):\s*(\d{1,3})%\s*(used|remaining|left)(?:\s*[·•\-|]\s*resets\s+(.+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines, .caseInsensitive]) else {
            return []
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        var windows: [QuotaWindow] = []

        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match,
                  let nameRange = Range(match.range(at: 1), in: text),
                  let pctRange = Range(match.range(at: 2), in: text),
                  let modeRange = Range(match.range(at: 3), in: text),
                  let pctValue = Int(text[pctRange]) else {
                return
            }

            let rawLabel = text[nameRange].trimmingCharacters(in: .whitespaces)
            let modeWord = text[modeRange].lowercased()
            let usedPercent = modeWord == "used" ? pctValue : (100 - pctValue)

            var resetClause: String?
            if match.range(at: 4).location != NSNotFound,
               let rRange = Range(match.range(at: 4), in: text) {
                resetClause = text[rRange].trimmingCharacters(in: .whitespaces)
            }

            let resetsAt = resetClause.flatMap { parseClaudeResetDate($0, referenceDate: referenceDate) }
            let lower = rawLabel.lowercased()
            let kind: WindowKind
            let duration: Int?
            let title: String

            if lower.contains("session") || lower.contains("5-hour") || lower.contains("5 hour") || lower.contains("five hour") {
                kind = .fiveHour
                duration = 300
                title = "5小时配额"
            } else if lower.contains("week") {
                if lower.contains("all models") || !windows.contains(where: { $0.kind == .weekly }) {
                    kind = .weekly
                } else {
                    kind = .other
                }
                duration = 10_080
                if let parenStart = rawLabel.firstIndex(of: "("),
                   let parenEnd = rawLabel.lastIndex(of: ")"),
                   parenStart < parenEnd {
                    let inner = rawLabel[rawLabel.index(after: parenStart)..<parenEnd]
                    title = inner.lowercased() == "all models" ? "每周配额" : "每周配额 (\(inner))"
                } else {
                    title = "每周配额"
                }
            } else {
                kind = .other
                duration = nil
                title = rawLabel
            }

            let slug = rawLabel.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")

            windows.append(QuotaWindow(
                id: "claude-\(slug)",
                title: title,
                kind: kind,
                usedPercent: usedPercent,
                durationMinutes: duration,
                resetsAt: resetsAt,
                resetRawText: resetClause
            ))
        }

        return windows
    }

    public static func parseClaudeResetDate(_ clause: String, referenceDate: Date) -> Date? {
        var working = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        var timeZone = TimeZone.current

        if let tzRegex = try? NSRegularExpression(pattern: #"\(([^)]+)\)\s*$"#),
           let match = tzRegex.firstMatch(in: working, range: NSRange(working.startIndex..., in: working)),
           let tzRange = Range(match.range(at: 1), in: working) {
            let tzID = String(working[tzRange]).trimmingCharacters(in: .whitespaces)
            if let resolved = TimeZone(identifier: tzID) ?? TimeZone(abbreviation: tzID) {
                timeZone = resolved
            }
            working.removeSubrange(Range(match.range, in: working)!)
            working = working.trimmingCharacters(in: .whitespaces)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let refYear = calendar.component(.year, from: referenceDate)

        let monthFormats = [
            "MMM d 'at' h:mma",
            "MMM d 'at' ha",
            "MMMM d 'at' h:mma",
            "MMMM d 'at' ha",
            "MMM d, yyyy 'at' h:mma",
            "MMM d, yyyy 'at' ha"
        ]
        let normalized = working
            .replacingOccurrences(of: " am", with: "am", options: .caseInsensitive)
            .replacingOccurrences(of: " pm", with: "pm", options: .caseInsensitive)

        for format in monthFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            if format.contains("yyyy") {
                formatter.dateFormat = format
                if let parsed = formatter.date(from: normalized) {
                    return parsed
                }
            } else {
                formatter.dateFormat = "yyyy " + format
                if let candidate = formatter.date(from: "\(refYear) \(normalized)") {
                    if candidate.timeIntervalSince(referenceDate) < -7 * 86_400,
                       let nextYear = formatter.date(from: "\(refYear + 1) \(normalized)") {
                        return nextYear
                    }
                    return candidate
                }
            }
        }

        let timeOnly = normalized.replacingOccurrences(of: #"^at\s+"#, with: "", options: .regularExpression)
        for format in ["h:mma", "ha", "HH:mm"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            if let parsedClock = formatter.date(from: timeOnly) {
                let clockComps = calendar.dateComponents([.hour, .minute], from: parsedClock)
                var targetComps = calendar.dateComponents([.year, .month, .day], from: referenceDate)
                targetComps.hour = clockComps.hour
                targetComps.minute = clockComps.minute
                targetComps.second = 0
                if var candidate = calendar.date(from: targetComps) {
                    if candidate <= referenceDate,
                       let tomorrow = calendar.date(byAdding: .day, value: 1, to: candidate) {
                        candidate = tomorrow
                    }
                    return candidate
                }
            }
        }

        return nil
    }
}

// MARK: - Codex (ChatGPT) JSON-RPC Parser

public enum CodexCLIParser {
    public static func parse(
        accountResult: [String: Any]?,
        rateLimitsResult: [String: Any],
        usageResult: [String: Any]? = nil,
        referenceDate: Date = Date()
    ) throws -> ProviderSnapshot {
        var accountLabel = "ChatGPT"
        if let account = accountResult?["account"] as? [String: Any] {
            let type = account["type"] as? String
            let plan = account["planType"] as? String
            if type == "chatgpt", let plan, !plan.isEmpty {
                accountLabel = "ChatGPT \(plan.capitalized)"
            } else if type == "apiKey" {
                accountLabel = "OpenAI API Key"
            }
        } else if let rateLimits = rateLimitsResult["rateLimits"] as? [String: Any],
                  let plan = rateLimits["planType"] as? String, !plan.isEmpty {
            accountLabel = "ChatGPT \(plan.capitalized)"
        }

        var windows: [QuotaWindow] = []
        if let buckets = rateLimitsResult["rateLimitsByLimitId"] as? [String: Any], !buckets.isEmpty {
            let sortedKeys = buckets.keys.sorted { lhs, rhs in
                if lhs == "codex" { return true }
                if rhs == "codex" { return false }
                return lhs < rhs
            }
            for key in sortedKeys {
                guard let snapshot = buckets[key] as? [String: Any] else { continue }
                windows.append(contentsOf: parseBucket(snapshot, fallbackID: key, isPrimaryBucket: key == "codex"))
            }
        } else if let snapshot = rateLimitsResult["rateLimits"] as? [String: Any] {
            windows = parseBucket(snapshot, fallbackID: "codex", isPrimaryBucket: true)
        }

        guard !windows.isEmpty else {
            throw CLIParserError.invalidFormat("Codex App Server 未返回配额窗口数据")
        }

        let tokenActivity = usageResult.flatMap(parseTokenActivity)

        return ProviderSnapshot(
            provider: .chatgpt,
            accountLabel: accountLabel,
            windows: windows,
            tokenActivity: tokenActivity,
            updatedAt: referenceDate
        )
    }

    private static func parseTokenActivity(_ result: [String: Any]) -> TokenActivitySnapshot? {
        var points: [TokenDailyPoint] = []
        if let rawBuckets = result["dailyUsageBuckets"] as? [[String: Any]] {
            points = rawBuckets.compactMap { row in
                guard let dateStr = row["startDate"] as? String,
                      let tokens = (row["tokens"] as? NSNumber)?.int64Value else {
                    return nil
                }
                return TokenDailyPoint(startDate: dateStr, tokens: tokens)
            }
        }
        let summary = result["summary"] as? [String: Any]
        let lifetime = (summary?["lifetimeTokens"] as? NSNumber)?.int64Value
        let peak = (summary?["peakDailyTokens"] as? NSNumber)?.int64Value
        let streak = (summary?["currentStreakDays"] as? NSNumber)?.int64Value
        if points.isEmpty && lifetime == nil { return nil }
        return TokenActivitySnapshot(
            dailyBuckets: points,
            lifetimeTokens: lifetime,
            peakDailyTokens: peak,
            currentStreakDays: streak
        )
    }

    private static func parseBucket(
        _ snapshot: [String: Any],
        fallbackID: String,
        isPrimaryBucket: Bool
    ) -> [QuotaWindow] {
        let limitID = (snapshot["limitId"] as? String) ?? fallbackID
        let rawName = snapshot["limitName"] as? String
        let groupName = rawName ?? (limitID == "codex" ? nil : limitID)
        var list: [QuotaWindow] = []

        if let primary = snapshot["primary"] as? [String: Any],
           let win = parseWindow(primary, id: "\(limitID)-primary", groupID: limitID, groupName: groupName, isPrimaryBucket: isPrimaryBucket) {
            list.append(win)
        }
        if let secondary = snapshot["secondary"] as? [String: Any],
           let win = parseWindow(secondary, id: "\(limitID)-secondary", groupID: limitID, groupName: groupName, isPrimaryBucket: isPrimaryBucket) {
            list.append(win)
        }
        return list
    }

    private static func parseWindow(
        _ obj: [String: Any],
        id: String,
        groupID: String,
        groupName: String?,
        isPrimaryBucket: Bool
    ) -> QuotaWindow? {
        guard let usedPercent = (obj["usedPercent"] as? NSNumber)?.intValue else {
            return nil
        }
        let duration = (obj["windowDurationMins"] as? NSNumber)?.intValue
        let resetEpoch = (obj["resetsAt"] as? NSNumber)?.doubleValue
        let resetsAt = resetEpoch.map { Date(timeIntervalSince1970: $0) }

        let kind: WindowKind
        let baseTitle: String
        switch duration {
        case 300:
            kind = isPrimaryBucket ? .fiveHour : .other
            baseTitle = "5小时配额"
        case 10_080:
            kind = isPrimaryBucket ? .weekly : .other
            baseTitle = "每周配额"
        case let mins? where mins > 0:
            kind = .other
            baseTitle = mins % 60 == 0 ? "\(mins / 60)小时配额" : "\(mins)分钟配额"
        default:
            kind = .other
            baseTitle = "配额窗口"
        }

        let title = if let groupName, !groupName.isEmpty {
            "\(groupName) · \(baseTitle)"
        } else {
            baseTitle
        }

        return QuotaWindow(
            id: id,
            groupID: groupID,
            groupName: groupName,
            title: title,
            kind: kind,
            usedPercent: usedPercent,
            durationMinutes: duration,
            resetsAt: resetsAt
        )
    }
}

// MARK: - Antigravity CLI Parser

public enum AntigravityCLIParser {
    public static func parseUsageOutput(
        _ rawData: Data,
        referenceDate: Date = Date()
    ) throws -> ProviderSnapshot {
        let rawText = String(data: rawData, encoding: .utf8) ?? ""
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIParserError.emptyOutput
        }

        if let jsonObj = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
            if let command = jsonObj["command"] as? [String: Any],
               let data = command["data"] as? [String: Any],
               let groups = data["groups"] as? [[String: Any]] {
                let windows = parseJSONGroups(groups)
                if !windows.isEmpty {
                    return ProviderSnapshot(
                        provider: .antigravity,
                        accountLabel: "Google Antigravity",
                        windows: windows,
                        updatedAt: referenceDate
                    )
                }
            }
            if let responseText = jsonObj["response"] as? String {
                let fallback = parsePlainLines(ANSIStripper.strip(responseText))
                if !fallback.isEmpty {
                    return ProviderSnapshot(
                        provider: .antigravity,
                        accountLabel: "Google Antigravity",
                        windows: fallback,
                        updatedAt: referenceDate
                    )
                }
            }
        }

        let clean = ANSIStripper.strip(rawText)
        if clean.localizedCaseInsensitiveContains("not signed in") {
            throw CLIParserError.unauthenticated("Antigravity CLI 未登录，请先在终端运行 agy 登录")
        }

        let fallbackWindows = parsePlainLines(clean)
        guard !fallbackWindows.isEmpty else {
            throw CLIParserError.invalidFormat("未能从 Antigravity CLI 解析出配额信息")
        }

        return ProviderSnapshot(
            provider: .antigravity,
            accountLabel: "Google Antigravity",
            windows: fallbackWindows,
            updatedAt: referenceDate
        )
    }

    private static func parseJSONGroups(_ groups: [[String: Any]]) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        for group in groups {
            let groupName = group["name"] as? String ?? "Models"
            let groupDesc = group["description"] as? String
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }

            let sortedBuckets = buckets.sorted { lhs, rhs in
                let lw = (lhs["window"] as? String) ?? ""
                let rw = (rhs["window"] as? String) ?? ""
                if lw == "5h" && rw != "5h" { return true }
                if rw == "5h" && lw != "5h" { return false }
                return lw < rw
            }

            for bucket in sortedBuckets {
                let id = (bucket["id"] as? String) ?? UUID().uuidString
                let windowCode = (bucket["window"] as? String)?.lowercased() ?? ""
                let rawFraction = (bucket["remaining_fraction"] as? NSNumber)?.doubleValue
                guard let rawFraction else { continue }
                let remainingPct = min(100, max(0, Int((rawFraction * 100.0).rounded())))
                let usedPct = 100 - remainingPct
                let resetStr = bucket["reset_time"] as? String
                let resetsAt = resetStr.flatMap(parseISO8601)

                let kind: WindowKind
                let duration: Int?
                let title: String
                if windowCode == "5h" || id.contains("5h") {
                    kind = .fiveHour
                    duration = 300
                    title = "5小时配额"
                } else if windowCode == "weekly" || id.contains("weekly") {
                    kind = .weekly
                    duration = 10_080
                    title = "每周配额"
                } else {
                    kind = .other
                    duration = nil
                    title = (bucket["name"] as? String) ?? "配额"
                }

                windows.append(QuotaWindow(
                    id: "agy-\(id)",
                    groupID: id,
                    groupName: groupName,
                    title: title,
                    kind: kind,
                    usedPercent: usedPct,
                    durationMinutes: duration,
                    resetsAt: resetsAt,
                    resetRawText: resetStr,
                    detailText: (bucket["description"] as? String) ?? groupDesc
                ))
            }
        }
        return windows
    }

    private static func parsePlainLines(_ text: String) -> [QuotaWindow] {
        let pattern = #"^(.+?)\s+(Weekly Limit Remaining|Five Hour Limit Remaining)\s+(\d{1,3})%\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return []
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        var windows: [QuotaWindow] = []
        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match,
                  let gRange = Range(match.range(at: 1), in: text),
                  let kRange = Range(match.range(at: 2), in: text),
                  let pRange = Range(match.range(at: 3), in: text),
                  let tRange = Range(match.range(at: 4), in: text),
                  let remPct = Int(text[pRange]) else {
                return
            }
            let groupName = text[gRange].trimmingCharacters(in: .whitespaces)
            let kindText = String(text[kRange])
            let timeStr = text[tRange].trimmingCharacters(in: .whitespaces)
            let isFiveHour = kindText.localizedCaseInsensitiveContains("Five Hour")
            let resetsAt = parseISO8601(timeStr) ?? parseLocalTimestamp(timeStr)

            windows.append(QuotaWindow(
                id: "agy-\(groupName.lowercased().replacingOccurrences(of: " ", with: "-"))-\(isFiveHour ? "5h" : "weekly")",
                groupID: groupName.lowercased(),
                groupName: groupName,
                title: isFiveHour ? "5小时配额" : "每周配额",
                kind: isFiveHour ? .fiveHour : .weekly,
                usedPercent: 100 - min(100, max(0, remPct)),
                durationMinutes: isFiveHour ? 300 : 10_080,
                resetsAt: resetsAt,
                resetRawText: timeStr
            ))
        }
        return windows
    }

    public static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: value) {
            return d.timeIntervalSince1970 > 946_684_800 ? d : nil
        }

        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let d = basic.date(from: value) {
            return d.timeIntervalSince1970 > 946_684_800 ? d : nil
        }
        return nil
    }

    private static func parseLocalTimestamp(_ value: String) -> Date? {
        let cleaned = value.replacingOccurrences(of: #"\s+[A-Z]{2,5}$"#, with: "", options: .regularExpression)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        if let d = formatter.date(from: cleaned) {
            return d.timeIntervalSince1970 > 946_684_800 ? d : nil
        }
        return nil
    }
}

// MARK: - DeepSeek DSH Platform & API Balance Parser

public enum DeepSeekCLIParser {
    public static func parseBalanceOutput(
        _ rawData: Data,
        sourceLabel: String = "DSH 已登录账户",
        referenceDate: Date = Date()
    ) throws -> ProviderSnapshot {
        let rawText = String(data: rawData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawText.isEmpty else {
            throw CLIParserError.emptyOutput
        }

        if let jsonObj = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
            // 1. DSH Platform get_user_summary envelope:
            // { "code": 0, "data": { "biz_code": 0, "biz_data": { "normal_wallets": [...], "bonus_wallets": [...], "total_costs": [...] } } }
            if let code = (jsonObj["code"] as? NSNumber)?.intValue {
                if code == 40003 {
                    throw CLIParserError.unauthenticated("DSH 登录令牌已过期，请在 DSH 中重新登录")
                }
                if code == 0,
                   let dataObj = jsonObj["data"] as? [String: Any],
                   let bizCode = (dataObj["biz_code"] as? NSNumber)?.intValue,
                   bizCode == 0,
                   let bizData = dataObj["biz_data"] as? [String: Any] {
                    let items = parseDSHWallets(bizData)
                    guard !items.isEmpty else {
                        throw CLIParserError.invalidFormat("DSH 平台未返回有效钱包记录")
                    }
                    let hasPositive = items.contains { $0.numericTotal > 0 }
                    return ProviderSnapshot(
                        provider: .deepseek,
                        accountLabel: sourceLabel,
                        balances: items,
                        isAvailable: hasPositive,
                        updatedAt: referenceDate
                    )
                }
            }

            // 2. Standard OpenAPI /user/balance response:
            if let errorObj = jsonObj["error"] as? [String: Any],
               let msg = errorObj["message"] as? String {
                throw CLIParserError.unauthenticated("DeepSeek API 错误：\(msg)")
            }
            if let infos = jsonObj["balance_infos"] as? [[String: Any]], !infos.isEmpty {
                let isAvailable = jsonObj["is_available"] as? Bool
                let balances = infos.compactMap { item -> DeepSeekBalanceItem? in
                    guard let currency = item["currency"] as? String,
                          let total = formatDecimalString(item["total_balance"]) else {
                        return nil
                    }
                    let granted = formatDecimalString(item["granted_balance"]) ?? "0.00"
                    let toppedUp = formatDecimalString(item["topped_up_balance"]) ?? "0.00"
                    return DeepSeekBalanceItem(
                        currency: currency,
                        totalBalance: total,
                        grantedBalance: granted,
                        toppedUpBalance: toppedUp
                    )
                }
                guard !balances.isEmpty else {
                    throw CLIParserError.invalidFormat("DeepSeek 返回空的余额列表")
                }
                return ProviderSnapshot(
                    provider: .deepseek,
                    accountLabel: sourceLabel,
                    balances: balances,
                    isAvailable: isAvailable,
                    updatedAt: referenceDate
                )
            }
        }

        // 3. Plain-text fallback for custom CLI scripts
        let clean = ANSIStripper.strip(rawText)
        if let regex = try? NSRegularExpression(pattern: #"(¥|\$|CNY|USD)?\s*([0-9]+(?:\.[0-9]+)?)"#, options: .caseInsensitive),
           let match = regex.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
           let numRange = Range(match.range(at: 2), in: clean) {
            var currency = "CNY"
            if match.range(at: 1).location != NSNotFound,
               let curRange = Range(match.range(at: 1), in: clean) {
                let token = clean[curRange].uppercased()
                currency = (token == "$" || token == "USD") ? "USD" : "CNY"
            }
            let amount = formatDecimalString(String(clean[numRange])) ?? "0.00"
            return ProviderSnapshot(
                provider: .deepseek,
                accountLabel: "自定义 CLI",
                balances: [DeepSeekBalanceItem(currency: currency, totalBalance: amount, toppedUpBalance: amount)],
                isAvailable: (Double(amount) ?? 0) > 0,
                updatedAt: referenceDate
            )
        }

        throw CLIParserError.invalidFormat("无法解析 DeepSeek 额度输出")
    }

    private static func parseDSHWallets(_ bizData: [String: Any]) -> [DeepSeekBalanceItem] {
        let normalList = (bizData["normal_wallets"] as? [[String: Any]]) ?? []
        let bonusList = (bizData["bonus_wallets"] as? [[String: Any]]) ?? []
        let costList = (bizData["total_costs"] as? [[String: Any]]) ?? []

        var currencies: [String] = []
        var normalByCur: [String: Decimal] = [:]
        var bonusByCur: [String: Decimal] = [:]
        var costByCur: [String: Decimal] = [:]

        func registerCurrency(_ cur: String) {
            let upper = cur.uppercased()
            if !currencies.contains(upper) {
                currencies.append(upper)
            }
        }

        for row in normalList {
            guard let cur = row["currency"] as? String else { continue }
            registerCurrency(cur)
            normalByCur[cur.uppercased(), default: 0] += decimalValue(row["balance"])
        }
        for row in bonusList {
            guard let cur = row["currency"] as? String else { continue }
            registerCurrency(cur)
            bonusByCur[cur.uppercased(), default: 0] += decimalValue(row["balance"])
        }
        for row in costList {
            guard let cur = row["currency"] as? String else { continue }
            costByCur[cur.uppercased(), default: 0] += decimalValue(row["amount"])
        }

        return currencies.map { cur in
            let toppedUp = normalByCur[cur] ?? 0
            let granted = bonusByCur[cur] ?? 0
            let total = toppedUp + granted
            let cost = costByCur[cur]
            return DeepSeekBalanceItem(
                currency: cur,
                totalBalance: formatTwoDecimals(total),
                grantedBalance: formatTwoDecimals(granted),
                toppedUpBalance: formatTwoDecimals(toppedUp),
                totalHistoricalCost: cost.map(formatTwoDecimals)
            )
        }
    }

    private static func decimalValue(_ any: Any?) -> Decimal {
        if let str = any as? String, let dec = Decimal(string: str, locale: Locale(identifier: "en_US_POSIX")) {
            return dec
        }
        if let num = any as? NSNumber {
            return num.decimalValue
        }
        return 0
    }

    private static func formatDecimalString(_ any: Any?) -> String? {
        if let str = any as? String, let dec = Decimal(string: str, locale: Locale(identifier: "en_US_POSIX")) {
            return formatTwoDecimals(dec)
        }
        if let num = any as? NSNumber {
            return formatTwoDecimals(num.decimalValue)
        }
        return nil
    }

    private static func formatTwoDecimals(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }
}
