import XCTest
@testable import UsageCore

final class UsageNormalizationTests: XCTestCase {
    func testCodexRateLimitResponseMapsPrimaryAndSecondaryWindows() throws {
        let json = """
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": null,
            "primary": { "usedPercent": 33, "windowDurationMins": 300, "resetsAt": 1779213628 },
            "secondary": { "usedPercent": 12, "windowDurationMins": 10080, "resetsAt": 1779590177 },
            "credits": null,
            "planType": "pro",
            "rateLimitReachedType": null
          },
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "limitName": null,
              "primary": { "usedPercent": 33, "windowDurationMins": 300, "resetsAt": 1779213628 },
              "secondary": { "usedPercent": 12, "windowDurationMins": 10080, "resetsAt": 1779590177 },
              "credits": null,
              "planType": "pro",
              "rateLimitReachedType": null
            }
          }
        }
        """.data(using: .utf8)!

        let usage = try CodexUsageParser.parse(
            data: json,
            accountID: "pooi",
            displayName: "pooi"
        )

        XCTAssertEqual(usage.provider, .codex)
        XCTAssertEqual(usage.accountID, "pooi")
        XCTAssertEqual(usage.displayName, "pooi")
        XCTAssertEqual(usage.fiveHourUsedPercent, 33)
        XCTAssertEqual(usage.weeklyUsedPercent, 12)
        XCTAssertEqual(usage.planName, "pro")
        XCTAssertEqual(usage.fiveHourResetAt?.timeIntervalSince1970, 1_779_213_628)
        XCTAssertEqual(usage.weeklyResetAt?.timeIntervalSince1970, 1_779_590_177)
    }

    func testClaudeUsageResponseMapsFiveHourAndSevenDayUtilization() throws {
        let json = """
        {
          "five_hour": {
            "utilization": 0.33,
            "resets_at": "2026-05-19T18:00:28Z"
          },
          "seven_day": {
            "utilization": 0.12,
            "resets_at": "2026-05-24T14:36:17Z"
          }
        }
        """.data(using: .utf8)!

        let usage = try ClaudeUsageParser.parse(
            data: json,
            accountID: "main",
            displayName: "main"
        )

        XCTAssertEqual(usage.provider, .claude)
        XCTAssertEqual(usage.accountID, "main")
        XCTAssertEqual(usage.displayName, "main")
        XCTAssertEqual(usage.fiveHourUsedPercent, 33)
        XCTAssertEqual(usage.weeklyUsedPercent, 12)
    }

    func testClaudeRelayUsageResponseMapsWindowRequestsAndWeeklyOpus() throws {
        let json = """
        {
          "success": true,
          "data": {
            "name": "example-max-plan",
            "limits": {
              "rateLimitRequests": 2500,
              "weeklyOpusCostLimit": 2500,
              "currentWindowRequests": 250,
              "weeklyOpusCost": 500,
              "windowEndTime": 1779218454780,
              "weeklyResetDay": 1,
              "weeklyResetHour": 0
            }
          }
        }
        """.data(using: .utf8)!

        let usage = try ClaudeRelayUsageParser.parse(
            data: json,
            accountID: "relay:example",
            displayName: "relay",
            now: Date(timeIntervalSince1970: 1_779_200_000)
        )

        XCTAssertEqual(usage.provider, .claudeRelay)
        XCTAssertEqual(usage.accountID, "relay:example")
        XCTAssertEqual(usage.displayName, "relay")
        XCTAssertEqual(usage.fiveHourUsedPercent, 10)
        XCTAssertEqual(usage.weeklyUsedPercent, 20)
        XCTAssertEqual(usage.fiveHourDisplayText, "5h 90%")
        XCTAssertEqual(usage.weeklyDisplayText, "1w 80%")
        XCTAssertEqual(usage.planName, "example-max-plan")
        XCTAssertEqual(usage.compactProviderCode, "C2")
    }

    func testDisplayRowsUseQuestionMarkForMissingValues() {
        let usage = ProviderAccountUsage(
            provider: .claude,
            accountID: "main",
            displayName: "main",
            fiveHourUsedPercent: nil,
            weeklyUsedPercent: 44,
            fiveHourResetAt: nil,
            weeklyResetAt: nil,
            planName: nil,
            errorMessage: "offline",
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(usage.fiveHourDisplayText, "5h ?")
        XCTAssertEqual(usage.weeklyDisplayText, "1w 56%")
        XCTAssertEqual(usage.compactProviderLabel, "◆ C1")
    }

    func testDisplayRowsUseRemainingPercentInsteadOfUsedPercent() {
        let usage = ProviderAccountUsage(
            provider: .codex,
            accountID: "main",
            displayName: "main",
            fiveHourUsedPercent: 33,
            weeklyUsedPercent: 12,
            fiveHourResetAt: nil,
            weeklyResetAt: nil,
            planName: nil,
            errorMessage: nil,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(usage.fiveHourDisplayText, "5h 67%")
        XCTAssertEqual(usage.weeklyDisplayText, "1w 88%")
    }

    func testFiveHourResetCountdownFloorsToHoursWhenAtLeastOneHourRemains() {
        let now = Date(timeIntervalSince1970: 1_000)
        let usage = ProviderAccountUsage(
            provider: .codex,
            accountID: "main",
            displayName: "main",
            fiveHourUsedPercent: 33,
            weeklyUsedPercent: 12,
            fiveHourResetAt: now.addingTimeInterval((4 * 60 * 60) + (30 * 60)),
            weeklyResetAt: nil,
            planName: nil,
            errorMessage: nil,
            updatedAt: now
        )

        XCTAssertEqual(usage.fiveHourResetCountdownText(now: now), "4h")
    }

    func testFiveHourResetCountdownFloorsToMinutesWhenUnderOneHourRemains() {
        let now = Date(timeIntervalSince1970: 1_000)
        let usage = ProviderAccountUsage(
            provider: .claude,
            accountID: "main",
            displayName: "main",
            fiveHourUsedPercent: 33,
            weeklyUsedPercent: 12,
            fiveHourResetAt: now.addingTimeInterval(30 * 60),
            weeklyResetAt: nil,
            planName: nil,
            errorMessage: nil,
            updatedAt: now
        )

        XCTAssertEqual(usage.fiveHourResetCountdownText(now: now), "30m")
    }

    func testFiveHourResetCountdownUsesNowForExpiredOrSubMinuteReset() {
        let now = Date(timeIntervalSince1970: 1_000)
        let usage = ProviderAccountUsage(
            provider: .claudeRelay,
            accountID: "relay",
            displayName: "relay",
            fiveHourUsedPercent: 33,
            weeklyUsedPercent: 12,
            fiveHourResetAt: now.addingTimeInterval(59),
            weeklyResetAt: nil,
            planName: nil,
            errorMessage: nil,
            updatedAt: now
        )

        XCTAssertEqual(usage.fiveHourResetCountdownText(now: now), "now")
        XCTAssertEqual(usage.fiveHourResetCountdownText(now: now.addingTimeInterval(60)), "now")
    }

    func testFiveHourResetCountdownUsesQuestionMarkWhenResetTimeIsMissing() {
        let now = Date(timeIntervalSince1970: 1_000)
        let usage = ProviderAccountUsage(
            provider: .claudeRelay,
            accountID: "relay",
            displayName: "relay",
            fiveHourUsedPercent: 33,
            weeklyUsedPercent: 12,
            fiveHourResetAt: nil,
            weeklyResetAt: nil,
            planName: nil,
            errorMessage: nil,
            updatedAt: now
        )

        XCTAssertEqual(usage.fiveHourResetCountdownText(now: now), "?")
    }

    func testWidgetSnapshotMapsUsageRowsForDisplay() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let usage = ProviderAccountUsage(
            provider: .claude,
            accountID: "main",
            displayName: "main",
            fiveHourUsedPercent: 84,
            weeklyUsedPercent: 15,
            fiveHourResetAt: now.addingTimeInterval(90 * 60),
            weeklyResetAt: nil,
            planName: nil,
            errorMessage: nil,
            updatedAt: now
        )

        let snapshot = CodexUsageWidgetSnapshot(usages: [usage], now: now)

        XCTAssertEqual(snapshot.accounts.count, 1)
        XCTAssertEqual(snapshot.accounts[0].id, "main")
        XCTAssertEqual(snapshot.accounts[0].providerCode, "C1")
        XCTAssertEqual(snapshot.accounts[0].displayName, "main")
        XCTAssertEqual(snapshot.accounts[0].fiveHourRemainingPercent, 16)
        XCTAssertEqual(snapshot.accounts[0].weeklyRemainingPercent, 85)
        XCTAssertEqual(snapshot.accounts[0].fiveHourResetText, "1h")
        XCTAssertEqual(snapshot.accounts[0].providerColorKey, "claude")
        XCTAssertEqual(snapshot.accounts[0].hasError, false)
    }

    func testWidgetSnapshotChoosesTightestFiveHourAccount() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let codex = ProviderAccountUsage(
            provider: .codex,
            accountID: "codex",
            displayName: "codex",
            fiveHourUsedPercent: 20,
            weeklyUsedPercent: 10,
            fiveHourResetAt: now.addingTimeInterval(4 * 60 * 60),
            weeklyResetAt: nil,
            planName: nil,
            errorMessage: nil,
            updatedAt: now
        )
        let claude = ProviderAccountUsage(
            provider: .claude,
            accountID: "claude",
            displayName: "claude",
            fiveHourUsedPercent: 91,
            weeklyUsedPercent: 10,
            fiveHourResetAt: now.addingTimeInterval(60 * 60),
            weeklyResetAt: nil,
            planName: nil,
            errorMessage: nil,
            updatedAt: now
        )

        let snapshot = CodexUsageWidgetSnapshot(usages: [codex, claude], now: now)

        XCTAssertEqual(snapshot.tightestAccount?.providerCode, "C1")
        XCTAssertEqual(snapshot.tightestAccount?.fiveHourRemainingPercent, 9)
    }

    func testWidgetSnapshotRoundTripsThroughJSON() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = CodexUsageWidgetSnapshot(
            updatedAt: now,
            accounts: [
                .init(
                    id: "codex:main",
                    providerCode: "Cx",
                    displayName: "main",
                    fiveHourRemainingPercent: 67,
                    weeklyRemainingPercent: 88,
                    fiveHourResetText: "4h",
                    providerColorKey: "codex",
                    hasError: false
                )
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(CodexUsageWidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }

    func testWidgetSnapshotWritesAndReadsFile() throws {
        let snapshot = CodexUsageWidgetSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_000),
            accounts: [
                .init(
                    id: "relay:main",
                    providerCode: "C2",
                    displayName: "relay",
                    fiveHourRemainingPercent: 99,
                    weeklyRemainingPercent: 98,
                    fiveHourResetText: "2h",
                    providerColorKey: "relay",
                    hasError: false
                )
            ]
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        try snapshot.write(to: url)
        let decoded = try CodexUsageWidgetSnapshot.read(from: url)

        XCTAssertEqual(decoded, snapshot)
        try? FileManager.default.removeItem(at: url)
    }

    func testConfigurationDecodesMultipleProviderAccounts() throws {
        let json = """
        {
          "refreshSeconds": 120,
          "accounts": [
            { "provider": "codex", "label": "pooi", "codexHome": "~/.codex/homes/pooi" },
            { "provider": "claude", "label": "main", "claudeHome": "~/.claude" },
            { "provider": "claudeRelay", "label": "relay", "relayApiID": "abc" }
          ]
        }
        """.data(using: .utf8)!

        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: json)

        XCTAssertEqual(configuration.refreshSeconds, 120)
        XCTAssertEqual(configuration.accounts.count, 3)
        XCTAssertEqual(configuration.accounts[0].provider, .codex)
        XCTAssertEqual(configuration.accounts[0].label, "pooi")
        XCTAssertEqual(configuration.accounts[0].codexHome, "~/.codex/homes/pooi")
        XCTAssertEqual(configuration.accounts[1].provider, .claude)
        XCTAssertEqual(configuration.accounts[1].claudeHome, "~/.claude")
        XCTAssertEqual(configuration.accounts[2].provider, .claudeRelay)
        XCTAssertEqual(configuration.accounts[2].label, "relay")
        XCTAssertEqual(configuration.accounts[2].relayApiID, "abc")
    }
}
