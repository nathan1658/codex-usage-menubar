import Foundation
import UsageCore

struct ConfigurationLoader {
    static var defaultConfigPath: String {
        expandTilde("~/.config/codex-usage-menubar/config.json")
    }

    static func load(path: String = defaultConfigPath) -> AppConfiguration {
        let expandedPath = expandTilde(path)
        if FileManager.default.fileExists(atPath: expandedPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: expandedPath)),
           let configuration = try? JSONDecoder().decode(AppConfiguration.self, from: data) {
            return configuration
        }

        return defaultConfiguration()
    }

    private static func defaultConfiguration() -> AppConfiguration {
        let candidates: [AccountConfiguration] = [
            AccountConfiguration(provider: .codex, label: "main", codexHome: "~/.codex"),
            AccountConfiguration(provider: .codex, label: "pooi", codexHome: "~/.codex/homes/pooi"),
            AccountConfiguration(provider: .codex, label: "wai", codexHome: "~/.codex/homes/wai"),
            AccountConfiguration(provider: .claude, label: "main", claudeHome: "~/.claude")
        ]

        let existing = candidates.filter { account in
            switch account.provider {
            case .codex:
                guard let home = account.codexHome else { return false }
                return FileManager.default.fileExists(atPath: expandTilde(home))
            case .claude:
                guard let home = account.claudeHome else { return false }
                return FileManager.default.fileExists(atPath: expandTilde(home))
            case .claudeRelay:
                return account.relayApiID != nil && account.relayStatsURL != nil
            }
        }

        return AppConfiguration(refreshSeconds: 300, accounts: existing.isEmpty ? candidates : existing)
    }
}
