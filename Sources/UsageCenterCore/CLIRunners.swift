import Darwin
import Foundation

public enum ExecutableLocator {
    public static func locate(
        binaryName: String,
        customPath: String = "",
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        let fm = FileManager.default
        let trimmedCustom = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty {
            let expanded = (trimmedCustom as NSString).expandingTildeInPath
            if fm.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }

        for dir in searchDirectories(homeDirectory: homeDirectory) {
            let candidate = dir.appendingPathComponent(binaryName)
            if fm.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    public static func enrichedEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: String] {
        var env = base
        let extraPaths = searchDirectories(homeDirectory: homeDirectory).map(\.path)
        let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        var merged: [String] = []
        var seen = Set<String>()
        for path in extraPaths + existing where !path.isEmpty && seen.insert(path).inserted {
            merged.append(path)
        }
        env["PATH"] = merged.joined(separator: ":")
        if env["HOME"] == nil {
            env["HOME"] = homeDirectory.path
        }
        return env
    }

    public static func searchDirectories(homeDirectory: URL) -> [URL] {
        var dirs: [URL] = [
            homeDirectory.appendingPathComponent(".local/bin"),
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
            homeDirectory.appendingPathComponent(".npm-global/bin"),
            homeDirectory.appendingPathComponent(".cargo/bin"),
            URL(fileURLWithPath: "/usr/bin"),
            URL(fileURLWithPath: "/bin")
        ]

        let nvmVersions = homeDirectory.appendingPathComponent(".nvm/versions/node")
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: nvmVersions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for nodeDir in entries.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                dirs.insert(nodeDir.appendingPathComponent("bin"), at: 4)
            }
        }
        return dirs
    }
}

public enum CLIRunnerError: LocalizedError {
    case binaryNotFound(String)
    case timeout(String)
    case executionFailed(String)
    case missingDeepSeekCredentials

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let name):
            return "未找到本地 CLI：\(name)，请确认已安装或在设置中指定路径"
        case .timeout(let name):
            return "\(name) 响应超时"
        case .executionFailed(let message):
            return message
        case .missingDeepSeekCredentials:
            return "尚未配置 DeepSeek API Key，请在设置中填入 Key 或配置本地 CLI 命令"
        }
    }
}

public struct ProcessResult: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32
}

private final class LockedProcessCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var outData = Data()
    private var errData = Data()
    private var resumed = false

    func appendStdout(_ chunk: Data) {
        lock.lock()
        if outData.count < 1_048_576 {
            outData.append(chunk)
        }
        lock.unlock()
    }

    func appendStderr(_ chunk: Data) {
        lock.lock()
        if errData.count < 65_536 {
            errData.append(chunk)
        }
        lock.unlock()
    }

    func claimCompletion(extraOut: Data = Data(), extraErr: Data = Data()) -> (stdout: Data, stderr: Data)? {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return nil }
        resumed = true
        if !extraOut.isEmpty, outData.count < 1_048_576 {
            outData.append(extraOut)
        }
        if !extraErr.isEmpty, errData.count < 65_536 {
            errData.append(extraErr)
        }
        return (outData, errData)
    }
}

public enum LocalProcessRunner {
    public static func run(
        executableURL: URL,
        arguments: [String],
        stdinData: Data? = nil,
        environment: [String: String]? = nil,
        workingDirectory: URL = FileManager.default.temporaryDirectory,
        timeoutSeconds: TimeInterval = 20
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outPipe = Pipe()
            let errPipe = Pipe()
            let inPipe = stdinData != nil ? Pipe() : nil

            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            process.environment = environment ?? ExecutableLocator.enrichedEnvironment()
            process.standardOutput = outPipe
            process.standardError = errPipe
            if let inPipe {
                process.standardInput = inPipe
                _ = fcntl(inPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            }

            let collector = LockedProcessCollector()

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                collector.appendStdout(chunk)
            }

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                collector.appendStderr(chunk)
            }

            let binaryName = executableURL.lastPathComponent
            let timeoutWork = DispatchWorkItem { [weak process] in
                guard let process, process.isRunning else { return }
                process.terminate()
                if collector.claimCompletion() != nil {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: CLIRunnerError.timeout(binaryName))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWork)

            process.terminationHandler = { proc in
                timeoutWork.cancel()
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil

                let remainingOut = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let remainingErr = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()

                if let captured = collector.claimCompletion(extraOut: remainingOut, extraErr: remainingErr) {
                    continuation.resume(returning: ProcessResult(
                        stdout: captured.stdout,
                        stderr: captured.stderr,
                        exitCode: proc.terminationStatus
                    ))
                }
            }

            do {
                try process.run()
                if let stdinData, let writer = inPipe?.fileHandleForWriting {
                    try? writer.write(contentsOf: stdinData)
                    try? writer.close()
                }
            } catch {
                timeoutWork.cancel()
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if collector.claimCompletion() != nil {
                    continuation.resume(throwing: CLIRunnerError.executionFailed("无法启动 \(binaryName)"))
                }
            }
        }
    }
}

private final class LockedCodexRPCState: @unchecked Sendable {
    struct StepOutcome {
        var shouldSendFollowups = false
        var fatalError: String?
        var completedPayload: (account: [String: Any]?, rateLimits: [String: Any])?
    }

    private let lock = NSLock()
    private var lineBuffer = Data()
    private var accountResult: [String: Any]?
    private var rateLimitsResult: [String: Any]?
    private var nonFatalAccountError: String?
    private var didSendFollowups = false
    private var completed = false

    func claimCompletion() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }

    func partialResults() -> (account: [String: Any]?, rateLimits: [String: Any]?) {
        lock.lock()
        defer { lock.unlock() }
        return (accountResult, rateLimitsResult)
    }

    func ingest(_ chunk: Data) -> StepOutcome {
        lock.lock()
        defer { lock.unlock() }

        var outcome = StepOutcome()
        lineBuffer.append(chunk)

        while let newlineIndex = lineBuffer.firstIndex(of: 0x0A) {
            let lineData = Data(lineBuffer[..<newlineIndex])
            lineBuffer.removeSubrange(...newlineIndex)
            guard !lineData.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let id = (obj["id"] as? NSNumber)?.intValue else {
                continue
            }

            if let err = obj["error"] as? [String: Any] {
                let msg = (err["message"] as? String) ?? "Codex RPC 请求失败"
                if id == 1 || id == 3 {
                    outcome.fatalError = msg
                } else {
                    nonFatalAccountError = msg
                }
                continue
            }

            guard let res = obj["result"] as? [String: Any] else { continue }
            if id == 1 && !didSendFollowups {
                didSendFollowups = true
                outcome.shouldSendFollowups = true
            } else if id == 2 {
                accountResult = res
            } else if id == 3 {
                rateLimitsResult = res
            }
        }

        if let rl = rateLimitsResult, accountResult != nil || nonFatalAccountError != nil {
            outcome.completedPayload = (account: accountResult, rateLimits: rl)
        }
        return outcome
    }
}

// MARK: - Provider CLI Fetchers

public enum ProviderUsageFetcher {
    public static func fetch(
        provider: ProviderID,
        preferences: UsageCenterPreferences,
        deepSeekKeyOverride: String? = nil
    ) async throws -> ProviderSnapshot {
        let customPath = preferences.config(for: provider).customCLIPath
        switch provider {
        case .claude:
            return try await fetchClaude(customPath: customPath)
        case .chatgpt:
            return try await fetchCodex(customPath: customPath)
        case .antigravity:
            return try await fetchAntigravity(customPath: customPath)
        case .deepseek:
            return try await fetchDeepSeek(
                customPath: customPath,
                customCommand: preferences.deepSeekCustomCommand,
                keyOverride: deepSeekKeyOverride
            )
        }
    }

    public static func fetchClaude(customPath: String = "") async throws -> ProviderSnapshot {
        guard let url = ExecutableLocator.locate(binaryName: "claude", customPath: customPath) else {
            throw CLIRunnerError.binaryNotFound("claude")
        }

        async let authTask = try? LocalProcessRunner.run(
            executableURL: url,
            arguments: ["auth", "status"],
            timeoutSeconds: 10
        )
        async let usageTask = LocalProcessRunner.run(
            executableURL: url,
            arguments: ["-p", "/usage", "--output-format", "json", "--no-session-persistence"],
            timeoutSeconds: 25
        )

        let usageResult = try await usageTask
        let authInfo = (await authTask).flatMap { ClaudeCLIParser.parseAuthStatus($0.stdout) }

        if usageResult.stdout.isEmpty, usageResult.exitCode != 0 {
            throw CLIRunnerError.executionFailed("Claude CLI 退出码 \(usageResult.exitCode)")
        }
        return try ClaudeCLIParser.parseUsageOutput(usageResult.stdout, authInfo: authInfo)
    }

    public static func fetchAntigravity(customPath: String = "") async throws -> ProviderSnapshot {
        guard let url = ExecutableLocator.locate(binaryName: "agy", customPath: customPath) else {
            throw CLIRunnerError.binaryNotFound("agy")
        }
        let result = try await LocalProcessRunner.run(
            executableURL: url,
            arguments: ["-p", "/usage", "--output-format", "json", "--print-timeout", "20s"],
            timeoutSeconds: 25
        )
        if result.stdout.isEmpty, result.exitCode != 0 {
            throw CLIRunnerError.executionFailed("Antigravity CLI 退出码 \(result.exitCode)")
        }
        return try AntigravityCLIParser.parseUsageOutput(result.stdout)
    }

    public static func fetchCodex(customPath: String = "") async throws -> ProviderSnapshot {
        guard let url = ExecutableLocator.locate(binaryName: "codex", customPath: customPath) else {
            throw CLIRunnerError.binaryNotFound("codex")
        }
        let responses = try await queryCodexAppServer(executableURL: url, timeoutSeconds: 18)
        return try CodexCLIParser.parse(
            accountResult: responses.account,
            rateLimitsResult: responses.rateLimits
        )
    }

    public static func fetchDeepSeek(
        customPath: String = "",
        customCommand: String = "",
        keyOverride: String? = nil
    ) async throws -> ProviderSnapshot {
        let resolvedKey = resolveDeepSeekKey(override: keyOverride)
        let trimmedCommand = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedCommand.isEmpty {
            let zsh = URL(fileURLWithPath: "/bin/zsh")
            var env = ExecutableLocator.enrichedEnvironment()
            if let resolvedKey, !resolvedKey.isEmpty {
                env["DEEPSEEK_API_KEY"] = resolvedKey
            }
            let result = try await LocalProcessRunner.run(
                executableURL: zsh,
                arguments: ["-lc", trimmedCommand],
                environment: env,
                timeoutSeconds: 20
            )
            guard result.exitCode == 0 || !result.stdout.isEmpty else {
                throw CLIRunnerError.executionFailed("自定义 DeepSeek CLI 命令执行失败（退出码 \(result.exitCode)）")
            }
            return try DeepSeekCLIParser.parseBalanceOutput(result.stdout)
        }

        guard let apiKey = resolvedKey, !apiKey.isEmpty else {
            throw CLIRunnerError.missingDeepSeekCredentials
        }

        guard let curlURL = ExecutableLocator.locate(binaryName: "curl", customPath: customPath) else {
            throw CLIRunnerError.binaryNotFound("curl")
        }

        let escapedKey = apiKey.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let curlConfig = """
        url = "https://api.deepseek.com/user/balance"
        header = "Authorization: Bearer \(escapedKey)"
        header = "Accept: application/json"
        """
        let result = try await LocalProcessRunner.run(
            executableURL: curlURL,
            arguments: ["--silent", "--show-error", "--location", "--max-time", "15", "--config", "-"],
            stdinData: Data(curlConfig.utf8),
            timeoutSeconds: 18
        )
        if result.stdout.isEmpty, result.exitCode != 0 {
            throw CLIRunnerError.executionFailed("curl 请求 DeepSeek 余额失败（退出码 \(result.exitCode)）")
        }
        return try DeepSeekCLIParser.parseBalanceOutput(result.stdout)
    }

    private static func resolveDeepSeekKey(override: String?) -> String? {
        if let override = override?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return override
        }
        if let keychainKey = KeychainHelper.readDeepSeekAPIKey() {
            return keychainKey
        }
        if let envKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !envKey.isEmpty {
            return envKey
        }
        return nil
    }

    private static func queryCodexAppServer(
        executableURL: URL,
        timeoutSeconds: TimeInterval
    ) async throws -> (account: [String: Any]?, rateLimits: [String: Any]) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let inPipe = Pipe()
            let outPipe = Pipe()
            let errPipe = Pipe()

            process.executableURL = executableURL
            process.arguments = ["app-server", "--listen", "stdio://"]
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            process.environment = ExecutableLocator.enrichedEnvironment()
            process.standardInput = inPipe
            process.standardOutput = outPipe
            process.standardError = errPipe

            let writer = inPipe.fileHandleForWriting
            _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)

            let rpcState = LockedCodexRPCState()

            @Sendable func sendJSON(_ dict: [String: Any]) {
                guard var data = try? JSONSerialization.data(withJSONObject: dict) else { return }
                data.append(0x0A)
                try? writer.write(contentsOf: data)
            }

            @Sendable func finish(_ result: Result<(account: [String: Any]?, rateLimits: [String: Any]), Error>) {
                guard rpcState.claimCompletion() else { return }
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                try? writer.close()
                if process.isRunning {
                    process.terminate()
                }
                continuation.resume(with: result)
            }

            let timeoutWork = DispatchWorkItem {
                finish(.failure(CLIRunnerError.timeout("codex app-server")))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWork)

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                if handle.availableData.isEmpty {
                    handle.readabilityHandler = nil
                }
            }

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }

                let outcome = rpcState.ingest(chunk)

                if let fatalError = outcome.fatalError {
                    timeoutWork.cancel()
                    finish(.failure(CLIRunnerError.executionFailed(fatalError)))
                    return
                }

                if outcome.shouldSendFollowups {
                    sendJSON(["method": "initialized", "params": [:]])
                    sendJSON(["method": "account/read", "id": 2, "params": ["refreshToken": false]])
                    sendJSON(["method": "account/rateLimits/read", "id": 3, "params": [:]])
                }

                if let payload = outcome.completedPayload {
                    timeoutWork.cancel()
                    finish(.success(payload))
                }
            }

            process.terminationHandler = { proc in
                timeoutWork.cancel()
                let partial = rpcState.partialResults()
                if let rl = partial.rateLimits {
                    finish(.success((account: partial.account, rateLimits: rl)))
                } else {
                    finish(.failure(CLIRunnerError.executionFailed("Codex App Server 提前退出（状态码 \(proc.terminationStatus)）")))
                }
            }

            do {
                try process.run()
                sendJSON([
                    "method": "initialize",
                    "id": 1,
                    "params": [
                        "clientInfo": [
                            "name": "usage_center",
                            "title": "UsageCenter",
                            "version": "1.0.0"
                        ]
                    ]
                ])
            } catch {
                timeoutWork.cancel()
                finish(.failure(CLIRunnerError.executionFailed("无法启动 codex app-server")))
            }
        }
    }
}
