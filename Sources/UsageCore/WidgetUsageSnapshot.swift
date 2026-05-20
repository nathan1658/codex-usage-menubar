import Foundation

public struct CodexUsageWidgetSnapshot: Codable, Equatable, Sendable {
    public static let widgetKind = "com.nathancheng.codex-usage-menubar.usage-widget"
    public static let widgetExtensionBundleIdentifier = "com.nathancheng.CodexUsageMenuBar.CodexUsageWidgetExtension"

    public let updatedAt: Date
    public let accounts: [Account]

    public init(updatedAt: Date, accounts: [Account]) {
        self.updatedAt = updatedAt
        self.accounts = accounts
    }

    public var tightestAccount: Account? {
        accounts.min { lhs, rhs in
            if lhs.hasError != rhs.hasError {
                return lhs.hasError
            }

            return (lhs.fiveHourRemainingPercent ?? -1) < (rhs.fiveHourRemainingPercent ?? -1)
        }
    }

    public static let empty = CodexUsageWidgetSnapshot(updatedAt: .distantPast, accounts: [])

    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexUsageMenuBar", isDirectory: true)
            .appendingPathComponent("usage-widget-snapshot.json")
    }

    public static var widgetExtensionSandboxFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(widgetExtensionBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support/CodexUsageMenuBar", isDirectory: true)
            .appendingPathComponent("usage-widget-snapshot.json")
    }

    public static func read(from url: URL = defaultFileURL) throws -> CodexUsageWidgetSnapshot {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CodexUsageWidgetSnapshot.self, from: data)
    }

    public func write(to url: URL = defaultFileURL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    public func writeForWidgetExtension() throws {
        try write(to: Self.defaultFileURL)
        try write(to: Self.widgetExtensionSandboxFileURL)
    }

    public struct Account: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let providerCode: String
        public let displayName: String
        public let fiveHourRemainingPercent: Int?
        public let weeklyRemainingPercent: Int?
        public let fiveHourResetText: String
        public let providerColorKey: String
        public let hasError: Bool

        public init(
            id: String,
            providerCode: String,
            displayName: String,
            fiveHourRemainingPercent: Int?,
            weeklyRemainingPercent: Int?,
            fiveHourResetText: String,
            providerColorKey: String,
            hasError: Bool
        ) {
            self.id = id
            self.providerCode = providerCode
            self.displayName = displayName
            self.fiveHourRemainingPercent = fiveHourRemainingPercent
            self.weeklyRemainingPercent = weeklyRemainingPercent
            self.fiveHourResetText = fiveHourResetText
            self.providerColorKey = providerColorKey
            self.hasError = hasError
        }
    }
}
