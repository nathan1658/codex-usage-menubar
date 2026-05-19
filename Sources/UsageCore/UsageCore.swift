import Foundation

public enum UsageProvider: String, Codable, Equatable, Sendable {
    case codex
    case claude
    case claudeRelay

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "codex":
            self = .codex
        case "claude":
            self = .claude
        case "clauderelay", "claude_relay", "relay":
            self = .claudeRelay
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown usage provider '\(value)'"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ProviderAccountUsage: Equatable, Sendable {
    public let provider: UsageProvider
    public let accountID: String
    public let displayName: String
    public let fiveHourUsedPercent: Int?
    public let weeklyUsedPercent: Int?
    public let fiveHourResetAt: Date?
    public let weeklyResetAt: Date?
    public let planName: String?
    public let errorMessage: String?
    public let updatedAt: Date

    public init(
        provider: UsageProvider,
        accountID: String,
        displayName: String,
        fiveHourUsedPercent: Int?,
        weeklyUsedPercent: Int?,
        fiveHourResetAt: Date?,
        weeklyResetAt: Date?,
        planName: String?,
        errorMessage: String?,
        updatedAt: Date
    ) {
        self.provider = provider
        self.accountID = accountID
        self.displayName = displayName
        self.fiveHourUsedPercent = fiveHourUsedPercent
        self.weeklyUsedPercent = weeklyUsedPercent
        self.fiveHourResetAt = fiveHourResetAt
        self.weeklyResetAt = weeklyResetAt
        self.planName = planName
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }

    public var fiveHourDisplayText: String {
        formatWindow(label: "5h", remainingPercent: fiveHourRemainingPercent)
    }

    public var weeklyDisplayText: String {
        formatWindow(label: "1w", remainingPercent: weeklyRemainingPercent)
    }

    public var fiveHourRemainingPercent: Int? {
        remainingPercent(from: fiveHourUsedPercent)
    }

    public var weeklyRemainingPercent: Int? {
        remainingPercent(from: weeklyUsedPercent)
    }

    public func fiveHourResetCountdownText(now: Date = Date()) -> String {
        resetCountdownText(until: fiveHourResetAt, now: now)
    }

    public var compactProviderCode: String {
        switch provider {
        case .codex:
            return "Cx"
        case .claude:
            return "C1"
        case .claudeRelay:
            return "C2"
        }
    }

    public var compactProviderLabel: String {
        switch provider {
        case .codex:
            return "◈ Cx"
        case .claude:
            return "◆ C1"
        case .claudeRelay:
            return "◇ C2"
        }
    }

    private func formatWindow(label: String, remainingPercent: Int?) -> String {
        guard let remainingPercent else {
            return "\(label) ?"
        }

        return "\(label) \(remainingPercent)%"
    }

    private func remainingPercent(from usedPercent: Int?) -> Int? {
        guard let usedPercent else {
            return nil
        }
        return 100 - usedPercent.clamped(to: 0...100)
    }

    private func resetCountdownText(until resetAt: Date?, now: Date) -> String {
        guard let resetAt else {
            return "?"
        }

        let remainingSeconds = max(0, Int(resetAt.timeIntervalSince(now)))
        let remainingMinutes = remainingSeconds / 60
        if remainingMinutes < 1 {
            return "now"
        }

        let remainingHours = remainingMinutes / 60
        if remainingHours >= 1 {
            return "\(remainingHours)h"
        }

        return "\(remainingMinutes)m"
    }

    public func withError(_ message: String, updatedAt: Date = Date()) -> ProviderAccountUsage {
        ProviderAccountUsage(
            provider: provider,
            accountID: accountID,
            displayName: displayName,
            fiveHourUsedPercent: fiveHourUsedPercent,
            weeklyUsedPercent: weeklyUsedPercent,
            fiveHourResetAt: fiveHourResetAt,
            weeklyResetAt: weeklyResetAt,
            planName: planName,
            errorMessage: message,
            updatedAt: updatedAt
        )
    }
}

public enum UsageParseError: Error, Equatable {
    case missingRateLimits
    case missingRelayLimits
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public let refreshSeconds: TimeInterval
    public let accounts: [AccountConfiguration]

    public init(refreshSeconds: TimeInterval, accounts: [AccountConfiguration]) {
        self.refreshSeconds = refreshSeconds
        self.accounts = accounts
    }
}

public struct AccountConfiguration: Codable, Equatable, Sendable {
    public let provider: UsageProvider
    public let label: String
    public let codexHome: String?
    public let claudeHome: String?
    public let relayApiID: String?
    public let relayStatsURL: String?
    public let relayReferrer: String?

    public init(
        provider: UsageProvider,
        label: String,
        codexHome: String? = nil,
        claudeHome: String? = nil,
        relayApiID: String? = nil,
        relayStatsURL: String? = nil,
        relayReferrer: String? = nil
    ) {
        self.provider = provider
        self.label = label
        self.codexHome = codexHome
        self.claudeHome = claudeHome
        self.relayApiID = relayApiID
        self.relayStatsURL = relayStatsURL
        self.relayReferrer = relayReferrer
    }

    public var stableID: String {
        "\(provider.rawValue):\(label)"
    }
}

public enum CodexUsageParser {
    public static func parse(data: Data, accountID: String, displayName: String, now: Date = Date()) throws -> ProviderAccountUsage {
        let response = try JSONDecoder().decode(CodexRateLimitsResponse.self, from: data)
        guard let snapshot = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits else {
            throw UsageParseError.missingRateLimits
        }

        return ProviderAccountUsage(
            provider: .codex,
            accountID: accountID,
            displayName: displayName,
            fiveHourUsedPercent: snapshot.primary?.usedPercent.roundedPercent,
            weeklyUsedPercent: snapshot.secondary?.usedPercent.roundedPercent,
            fiveHourResetAt: snapshot.primary?.resetDate,
            weeklyResetAt: snapshot.secondary?.resetDate,
            planName: snapshot.planType,
            errorMessage: nil,
            updatedAt: now
        )
    }
}

public enum ClaudeUsageParser {
    public static func parse(data: Data, accountID: String, displayName: String, now: Date = Date()) throws -> ProviderAccountUsage {
        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        return ProviderAccountUsage(
            provider: .claude,
            accountID: accountID,
            displayName: displayName,
            fiveHourUsedPercent: normalizedUtilization(response.fiveHour.utilization),
            weeklyUsedPercent: normalizedUtilization(response.sevenDay.utilization),
            fiveHourResetAt: parseISODate(response.fiveHour.resetsAt),
            weeklyResetAt: parseISODate(response.sevenDay.resetsAt),
            planName: nil,
            errorMessage: nil,
            updatedAt: now
        )
    }

    private static func normalizedUtilization(_ value: Double) -> Int {
        let percent = value <= 1 ? value * 100 : value
        return Int(percent.rounded()).clamped(to: 0...100)
    }
}

public enum ClaudeRelayUsageParser {
    public static func parse(data: Data, accountID: String, displayName: String, now: Date = Date()) throws -> ProviderAccountUsage {
        let response = try JSONDecoder().decode(ClaudeRelayUsageResponse.self, from: data)
        guard response.success == true, let limits = response.data?.limits else {
            throw UsageParseError.missingRelayLimits
        }

        return ProviderAccountUsage(
            provider: .claudeRelay,
            accountID: accountID,
            displayName: displayName,
            fiveHourUsedPercent: percentFrom(used: limits.currentWindowRequests, limit: limits.rateLimitRequests),
            weeklyUsedPercent: percentFrom(used: limits.weeklyOpusCost, limit: limits.weeklyOpusCostLimit),
            fiveHourResetAt: limits.windowEndTime.flatMap { Date(timeIntervalSince1970: $0 / 1000) },
            weeklyResetAt: nextWeeklyResetDate(day: limits.weeklyResetDay, hour: limits.weeklyResetHour, now: now),
            planName: response.data?.name,
            errorMessage: nil,
            updatedAt: now
        )
    }
}

private struct CodexRateLimitsResponse: Decodable {
    let rateLimits: CodexRateLimitSnapshot?
    let rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?
}

private struct CodexRateLimitSnapshot: Decodable {
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let planType: String?
}

private struct CodexRateLimitWindow: Decodable {
    let usedPercent: Double
    let resetsAt: TimeInterval?

    var resetDate: Date? {
        resetsAt.map(Date.init(timeIntervalSince1970:))
    }
}

private struct ClaudeUsageResponse: Decodable {
    let fiveHour: ClaudeUsageWindow
    let sevenDay: ClaudeUsageWindow

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct ClaudeUsageWindow: Decodable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

private struct ClaudeRelayUsageResponse: Decodable {
    let success: Bool?
    let data: ClaudeRelayUsageData?
}

private struct ClaudeRelayUsageData: Decodable {
    let name: String?
    let limits: ClaudeRelayLimits?
}

private struct ClaudeRelayLimits: Decodable {
    let rateLimitRequests: Double?
    let weeklyOpusCostLimit: Double?
    let currentWindowRequests: Double?
    let weeklyOpusCost: Double?
    let windowEndTime: TimeInterval?
    let weeklyResetDay: Int?
    let weeklyResetHour: Int?
}

private extension Double {
    var roundedPercent: Int {
        Int(rounded()).clamped(to: 0...100)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private func percentFrom(used: Double?, limit: Double?) -> Int? {
    guard let used, let limit else {
        return nil
    }

    guard limit > 0 else {
        return 0
    }

    return Int(((used * 100) / limit).rounded()).clamped(to: 0...100)
}

private func nextWeeklyResetDate(day resetDay: Int?, hour resetHour: Int?, now: Date) -> Date? {
    guard let resetDay, let resetHour else {
        return nil
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current

    let resetWeekday = ((resetDay % 7) + 1)
    let nowWeekday = calendar.component(.weekday, from: now)
    let nowHour = calendar.component(.hour, from: now)

    var daysAhead = (resetWeekday - nowWeekday + 7) % 7
    if daysAhead == 0 && nowHour >= resetHour {
        daysAhead = 7
    }

    guard let day = calendar.date(byAdding: .day, value: daysAhead, to: now) else {
        return nil
    }

    return calendar.date(bySettingHour: resetHour, minute: 0, second: 0, of: day)
}

private func parseISODate(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else {
        return nil
    }

    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractionalFormatter.date(from: value) {
        return date
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}
