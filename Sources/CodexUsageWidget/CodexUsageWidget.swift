import Foundation
import SwiftUI
import WidgetKit

struct UsageWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageWidgetEntry {
        UsageWidgetEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageWidgetEntry) -> Void) {
        completion(UsageWidgetEntry(date: .now, snapshot: loadSnapshot(preview: context.isPreview)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageWidgetEntry>) -> Void) {
        let date = Date()
        let entry = UsageWidgetEntry(date: date, snapshot: loadSnapshot(preview: context.isPreview))
        completion(Timeline(entries: [entry], policy: .after(date.addingTimeInterval(5 * 60))))
    }

    private func loadSnapshot(preview: Bool) -> CodexUsageWidgetSnapshot {
        if preview {
            return .preview
        }

        return (try? CodexUsageWidgetSnapshot.read()) ?? .empty
    }
}

struct UsageWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: CodexUsageWidgetSnapshot
}

@main
struct CodexUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexUsageWidget()
    }
}

struct CodexUsageWidget: Widget {
    let kind = CodexUsageWidgetSnapshot.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageWidgetProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AI Usage")
        .description("Shows Codex, Claude, and relay quota with reset timing.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: UsageWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallUsageWidget(snapshot: entry.snapshot)
        case .systemMedium:
            MediumUsageWidget(snapshot: entry.snapshot)
        case .systemLarge:
            LargeUsageWidget(snapshot: entry.snapshot)
        default:
            SmallUsageWidget(snapshot: entry.snapshot)
        }
    }
}

struct SmallUsageWidget: View {
    let snapshot: CodexUsageWidgetSnapshot

    var body: some View {
        if let account = snapshot.tightestAccount {
            VStack(alignment: .leading, spacing: 8) {
                HeaderRow(title: "AI", updatedAt: snapshot.updatedAt)

                Spacer(minLength: 0)

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(account.providerCode)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                    Text(percentText(account.fiveHourRemainingPercent))
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(riskColor(account.fiveHourRemainingPercent))
                        .monospacedDigit()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Label(account.fiveHourResetText, systemImage: "clock")
                    Text(weeklyText(account.weeklyRemainingPercent))
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

                QuotaBar(percent: account.fiveHourRemainingPercent, color: riskColor(account.fiveHourRemainingPercent))
            }
            .widgetPadding()
        } else {
            EmptyWidgetView()
        }
    }
}

struct MediumUsageWidget: View {
    let snapshot: CodexUsageWidgetSnapshot

    var body: some View {
        if snapshot.accounts.isEmpty {
            EmptyWidgetView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HeaderRow(title: "AI Usage", updatedAt: snapshot.updatedAt)

                HStack(alignment: .top, spacing: 10) {
                    ForEach(snapshot.accounts) { account in
                        AccountColumn(account: account)
                    }
                }
            }
            .widgetPadding()
        }
    }
}

struct LargeUsageWidget: View {
    let snapshot: CodexUsageWidgetSnapshot

    var body: some View {
        if snapshot.accounts.isEmpty {
            EmptyWidgetView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HeaderRow(title: "AI Usage", updatedAt: snapshot.updatedAt)

                if let account = snapshot.tightestAccount {
                    FocusAccountPanel(account: account)
                }

                VStack(spacing: 9) {
                    ForEach(snapshot.accounts) { account in
                        AccountRow(account: account)
                    }
                }
            }
            .widgetPadding()
        }
    }
}

struct HeaderRow: View {
    let title: String
    let updatedAt: Date

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Spacer()
            Text(updatedAt, style: .time)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

struct AccountColumn: View {
    let account: CodexUsageWidgetSnapshot.Account

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(providerColor(account.providerColorKey))
                    .frame(width: 7, height: 7)
                Text(account.providerCode)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }

            Text(percentText(account.fiveHourRemainingPercent))
                .font(.system(size: 25, weight: .black, design: .rounded))
                .foregroundStyle(riskColor(account.fiveHourRemainingPercent))
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 3) {
                Text("reset \(account.fiveHourResetText)")
                Text(weeklyText(account.weeklyRemainingPercent))
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)

            QuotaBar(percent: account.fiveHourRemainingPercent, color: riskColor(account.fiveHourRemainingPercent))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FocusAccountPanel: View {
    let account: CodexUsageWidgetSnapshot.Account

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tightest 5h")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(providerColor(account.providerColorKey))
                            .frame(width: 7, height: 7)
                        Text(account.providerCode)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                        Text(account.displayName)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(percentText(account.fiveHourRemainingPercent))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(riskColor(account.fiveHourRemainingPercent))
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                Label(account.fiveHourResetText, systemImage: "clock")
                Text(weeklyText(account.weeklyRemainingPercent))
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)

            QuotaBar(percent: account.fiveHourRemainingPercent, color: riskColor(account.fiveHourRemainingPercent))
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct AccountRow: View {
    let account: CodexUsageWidgetSnapshot.Account

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 9) {
                Text(account.providerCode)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .frame(width: 28, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text("resets in \(account.fiveHourResetText)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(percentText(account.fiveHourRemainingPercent))
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(riskColor(account.fiveHourRemainingPercent))
                        .monospacedDigit()
                    Text(weeklyText(account.weeklyRemainingPercent))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            QuotaBar(percent: account.fiveHourRemainingPercent, color: riskColor(account.fiveHourRemainingPercent))
        }
    }
}

struct EmptyWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Usage")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text("Open the menu-bar app once to load usage.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .widgetPadding()
    }
}

struct QuotaBar: View {
    let percent: Int?
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let fraction = CGFloat(max(0, min(percent ?? 0, 100))) / 100
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.tertiary)
                Capsule()
                    .fill(color)
                    .frame(width: max(4, proxy.size.width * fraction))
            }
        }
        .frame(height: 5)
    }
}

private func percentText(_ percent: Int?) -> String {
    percent.map(String.init) ?? "?"
}

private func percentLabel(_ percent: Int?) -> String {
    percent.map { "\($0)%" } ?? "?"
}

private func weeklyText(_ percent: Int?) -> String {
    "weekly \(percentLabel(percent))"
}

private func riskColor(_ percent: Int?) -> Color {
    guard let percent else {
        return .orange
    }
    if percent < 20 {
        return .red
    }
    if percent < 50 {
        return .yellow
    }
    return .primary
}

private func providerColor(_ key: String) -> Color {
    switch key {
    case "codex":
        return .blue
    case "claude":
        return .orange
    case "relay":
        return .purple
    default:
        return .secondary
    }
}

private extension View {
    func widgetPadding() -> some View {
        padding(14)
    }
}

private extension CodexUsageWidgetSnapshot {
    static let preview = CodexUsageWidgetSnapshot(
        updatedAt: Date(),
        accounts: [
            .init(
                id: "codex:preview",
                providerCode: "Cx",
                displayName: "Codex",
                fiveHourRemainingPercent: 67,
                weeklyRemainingPercent: 88,
                fiveHourResetText: "4h",
                providerColorKey: "codex",
                hasError: false
            ),
            .init(
                id: "claude:preview",
                providerCode: "C1",
                displayName: "Claude",
                fiveHourRemainingPercent: 16,
                weeklyRemainingPercent: 85,
                fiveHourResetText: "1h",
                providerColorKey: "claude",
                hasError: false
            ),
            .init(
                id: "relay:preview",
                providerCode: "C2",
                displayName: "Relay",
                fiveHourRemainingPercent: 99,
                weeklyRemainingPercent: 98,
                fiveHourResetText: "2h",
                providerColorKey: "relay",
                hasError: false
            )
        ]
    )
}
