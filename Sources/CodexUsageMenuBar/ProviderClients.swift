import Foundation
import UsageCore

enum UsageFetchError: Error, CustomStringConvertible {
    case missingCodexHome
    case missingClaudeToken
    case processTimedOut(String)
    case processFailed(String)
    case rpcFailed(String)
    case missingRPCResult
    case missingRelayConfiguration(String)
    case httpFailed(Int)
    case networkFailed(String)

    var description: String {
        switch self {
        case .missingCodexHome:
            return "missing Codex home"
        case .missingClaudeToken:
            return "missing Claude OAuth token"
        case .processTimedOut(let name):
            return "\(name) timed out"
        case .processFailed(let message):
            return message
        case .rpcFailed(let message):
            return message
        case .missingRPCResult:
            return "missing Codex rate limit response"
        case .missingRelayConfiguration(let field):
            return "missing Claude relay \(field)"
        case .httpFailed(let status):
            return "HTTP \(status)"
        case .networkFailed(let message):
            return message
        }
    }
}

protocol UsageProviderClient {
    func fetch(account: AccountConfiguration) throws -> ProviderAccountUsage
}

struct CodexProviderClient: UsageProviderClient {
    func fetch(account: AccountConfiguration) throws -> ProviderAccountUsage {
        guard let codexHome = account.codexHome else {
            throw UsageFetchError.missingCodexHome
        }

        let resultData = try readRateLimits(codexHome: expandTilde(codexHome))
        return try CodexUsageParser.parse(data: resultData, accountID: account.stableID, displayName: account.label)
    }

    private func readRateLimits(codexHome: String) throws -> Data {
        let process = Process()
        let codexExecutable = try CodexExecutable.resolve()
        process.executableURL = codexExecutable
        process.arguments = ["app-server", "--listen", "stdio://"]

        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = codexHome
        environment["PATH"] = CodexExecutable.pathEnvironment(for: codexExecutable, currentPath: environment["PATH"])
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let initSeen = DispatchSemaphore(value: 0)
        let resultSeen = DispatchSemaphore(value: 0)
        let outputState = CodexOutputState(initSeen: initSeen, resultSeen: resultSeen)

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputState.append(data)
        }

        do {
            try process.run()
        } catch {
            throw UsageFetchError.processFailed(error.localizedDescription)
        }

        let input = stdin.fileHandleForWriting
        input.write(Self.initializeRequestLine)

        guard initSeen.wait(timeout: .now() + 4) == .success else {
            terminate(process)
            throw UsageFetchError.processTimedOut("Codex initialize")
        }

        input.write(Self.rateLimitsRequestLine)

        guard resultSeen.wait(timeout: .now() + 6) == .success else {
            terminate(process)
            throw UsageFetchError.processTimedOut("Codex rate limits")
        }

        terminate(process)
        stdout.fileHandleForReading.readabilityHandler = nil

        return try extractResultFromJSONLines(outputState.data())
    }

    private func terminate(_ process: Process) {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    private func extractResultFromJSONLines(_ data: Data) throws -> Data {
        let text = String(data: data, encoding: .utf8) ?? ""
        for line in text.split(separator: "\n") {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  object["id"] as? Int == 2 else {
                continue
            }

            if let error = object["error"] as? [String: Any] {
                throw UsageFetchError.rpcFailed(error["message"] as? String ?? "Codex RPC failed")
            }

            guard let result = object["result"] else {
                throw UsageFetchError.missingRPCResult
            }

            return try JSONSerialization.data(withJSONObject: result)
        }

        throw UsageFetchError.missingRPCResult
    }

    private static let initializeRequestLine = ("""
    {"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-usage-menubar","title":"Codex Usage Menu Bar","version":"0.1.0"},"capabilities":{"experimentalApi":true,"requestAttestation":false,"optOutNotificationMethods":[]}}}
    """ + "\n").data(using: .utf8)!

    private static let rateLimitsRequestLine = ("""
    {"id":2,"method":"account/rateLimits/read"}
    """ + "\n").data(using: .utf8)!
}

private enum CodexExecutable {
    static func resolve() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_BINARY"], !override.isEmpty {
            let expanded = expandTilde(override)
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }

        for candidate in fixedCandidates() where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        if let nvmCandidate = newestNVMNodeCodex() {
            return URL(fileURLWithPath: nvmCandidate)
        }

        throw UsageFetchError.processFailed("codex executable not found")
    }

    private static func fixedCandidates() -> [String] {
        [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            expandTilde("~/.bun/bin/codex")
        ]
    }

    private static func newestNVMNodeCodex() -> String? {
        let nodeVersions = expandTilde("~/.nvm/versions/node")
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: nodeVersions) else {
            return nil
        }

        return versions
            .sorted { $0.localizedStandardCompare($1) == .orderedDescending }
            .map { "\(nodeVersions)/\($0)/bin/codex" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func pathEnvironment(for codexExecutable: URL, currentPath: String?) -> String {
        let codexBin = codexExecutable.deletingLastPathComponent().path
        let basePath = currentPath ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return "\(codexBin):\(basePath)"
    }
}

struct ClaudeProviderClient: UsageProviderClient {
    func fetch(account: AccountConfiguration) throws -> ProviderAccountUsage {
        let claudeHome = expandTilde(account.claudeHome ?? "~/.claude")
        guard let token = resolveOAuthToken(claudeHome: claudeHome) else {
            throw UsageFetchError.missingClaudeToken
        }

        let data = try fetchUsageData(token: token)
        return try ClaudeUsageParser.parse(data: data, accountID: account.stableID, displayName: account.label)
    }

    private func resolveOAuthToken(claudeHome: String) -> String? {
        if let token = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"], !token.isEmpty {
            return token
        }

        if let keychainToken = readTokenFromKeychain() {
            return keychainToken
        }

        return readTokenFromCredentialsFile(claudeHome: claudeHome)
    }

    private func readTokenFromKeychain() -> String? {
        guard let result = try? Shell.run(
            "/usr/bin/security",
            arguments: ["find-generic-password", "-s", "Claude Code-credentials", "-w"],
            timeout: 2
        ), !result.timedOut, result.exitCode == 0 else {
            return nil
        }

        return extractToken(from: result.stdout)
    }

    private func readTokenFromCredentialsFile(claudeHome: String) -> String? {
        let url = URL(fileURLWithPath: claudeHome).appendingPathComponent(".credentials.json")
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return extractToken(from: data)
    }

    private func extractToken(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private func fetchUsageData(token: String) throws -> Data {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw UsageFetchError.networkFailed("invalid Claude usage URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.34", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        let responseState = URLResponseState()

        URLSession.shared.dataTask(with: request) { data, response, error in
            responseState.update(
                data: data,
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                error: error
            )
            semaphore.signal()
        }.resume()

        guard semaphore.wait(timeout: .now() + 10) == .success else {
            throw UsageFetchError.processTimedOut("Claude usage")
        }

        let result = responseState.snapshot()

        if let responseError = result.error {
            throw UsageFetchError.networkFailed(responseError.localizedDescription)
        }

        guard let responseCode = result.statusCode, (200..<300).contains(responseCode) else {
            throw UsageFetchError.httpFailed(result.statusCode ?? 0)
        }

        return result.data ?? Data()
    }
}

struct ClaudeRelayProviderClient: UsageProviderClient {
    func fetch(account: AccountConfiguration) throws -> ProviderAccountUsage {
        let environment = ProcessInfo.processInfo.environment
        guard let apiID = configuredValue(account.relayApiID) ?? configuredValue(environment["CLAUDE_STATUSLINE_RELAY_API_ID"]) else {
            throw UsageFetchError.missingRelayConfiguration("api id")
        }
        guard let statsURL = configuredValue(account.relayStatsURL) ?? configuredValue(environment["CLAUDE_STATUSLINE_RELAY_STATS_URL"]) else {
            throw UsageFetchError.missingRelayConfiguration("stats URL")
        }
        let referrer = configuredValue(account.relayReferrer) ?? configuredValue(environment["CLAUDE_STATUSLINE_RELAY_REFERRER"])

        let data = try fetchRelayUsageData(apiID: apiID, statsURL: statsURL, referrer: referrer)
        return try ClaudeRelayUsageParser.parse(data: data, accountID: account.stableID, displayName: account.label)
    }

    private func fetchRelayUsageData(apiID: String, statsURL: String, referrer: String?) throws -> Data {
        guard let url = URL(string: statsURL) else {
            throw UsageFetchError.networkFailed("invalid Claude relay stats URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let referrer {
            request.setValue(referrer, forHTTPHeaderField: "Referer")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["apiId": apiID])

        let semaphore = DispatchSemaphore(value: 0)
        let responseState = URLResponseState()

        URLSession.shared.dataTask(with: request) { data, response, error in
            responseState.update(
                data: data,
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                error: error
            )
            semaphore.signal()
        }.resume()

        guard semaphore.wait(timeout: .now() + 10) == .success else {
            throw UsageFetchError.processTimedOut("Claude relay usage")
        }

        let result = responseState.snapshot()

        if let responseError = result.error {
            throw UsageFetchError.networkFailed(responseError.localizedDescription)
        }

        guard let responseCode = result.statusCode, (200..<300).contains(responseCode) else {
            throw UsageFetchError.httpFailed(result.statusCode ?? 0)
        }

        return result.data ?? Data()
    }

    private func configuredValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private final class CodexOutputState: @unchecked Sendable {
    private let lock = NSLock()
    private let initSeen: DispatchSemaphore
    private let resultSeen: DispatchSemaphore
    private var buffer = Data()
    private var initSignaled = false
    private var resultSignaled = false

    init(initSeen: DispatchSemaphore, resultSeen: DispatchSemaphore) {
        self.initSeen = initSeen
        self.resultSeen = resultSeen
    }

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        let text = String(data: buffer, encoding: .utf8) ?? ""
        if !initSignaled, text.contains("\"id\":1") {
            initSignaled = true
            initSeen.signal()
        }
        if !resultSignaled, text.contains("\"id\":2") {
            resultSignaled = true
            resultSeen.signal()
        }
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

private final class URLResponseState: @unchecked Sendable {
    private let lock = NSLock()
    private var dataValue: Data?
    private var statusCodeValue: Int?
    private var errorValue: Error?

    func update(data: Data?, statusCode: Int?, error: Error?) {
        lock.lock()
        dataValue = data
        statusCodeValue = statusCode
        errorValue = error
        lock.unlock()
    }

    func snapshot() -> (data: Data?, statusCode: Int?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        return (dataValue, statusCodeValue, errorValue)
    }
}
