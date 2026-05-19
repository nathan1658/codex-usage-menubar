import Foundation
import UsageCore

final class UsagePoller: @unchecked Sendable {
    private let configuration: AppConfiguration
    private let codexClient = CodexProviderClient()
    private let claudeClient = ClaudeProviderClient()
    private let claudeRelayClient = ClaudeRelayProviderClient()
    private let cacheLock = NSLock()
    private var lastSuccessfulUsage: [String: ProviderAccountUsage] = [:]

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    var refreshSeconds: TimeInterval {
        max(30, configuration.refreshSeconds)
    }

    func fetchAll() -> [ProviderAccountUsage] {
        let group = DispatchGroup()
        let store = UsageResultStore()

        for account in configuration.accounts {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                store.set(self.fetch(account: account), for: account.stableID)
                group.leave()
            }
        }

        group.wait()
        return configuration.accounts.compactMap { store.value(for: $0.stableID) }
    }

    private func fetch(account: AccountConfiguration) -> ProviderAccountUsage {
        do {
            let usage: ProviderAccountUsage
            switch account.provider {
            case .codex:
                usage = try codexClient.fetch(account: account)
            case .claude:
                usage = try claudeClient.fetch(account: account)
            case .claudeRelay:
                usage = try claudeRelayClient.fetch(account: account)
            }
            cacheLock.lock()
            lastSuccessfulUsage[account.stableID] = usage
            cacheLock.unlock()
            return usage
        } catch {
            let message = sanitizedErrorMessage(String(describing: error))
            cacheLock.lock()
            let cached = lastSuccessfulUsage[account.stableID]
            cacheLock.unlock()

            if let cached {
                return cached.withError(message)
            }

            return ProviderAccountUsage(
                provider: account.provider,
                accountID: account.stableID,
                displayName: account.label,
                fiveHourUsedPercent: nil,
                weeklyUsedPercent: nil,
                fiveHourResetAt: nil,
                weeklyResetAt: nil,
                planName: nil,
                errorMessage: message,
                updatedAt: Date()
            )
        }
    }

    private func sanitizedErrorMessage(_ message: String) -> String {
        let firstLine = message
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? message

        if firstLine.count <= 160 {
            return firstLine
        }

        return String(firstLine.prefix(157)) + "..."
    }
}

private final class UsageResultStore: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: ProviderAccountUsage] = [:]

    func set(_ usage: ProviderAccountUsage, for key: String) {
        lock.lock()
        values[key] = usage
        lock.unlock()
    }

    func value(for key: String) -> ProviderAccountUsage? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }
}
