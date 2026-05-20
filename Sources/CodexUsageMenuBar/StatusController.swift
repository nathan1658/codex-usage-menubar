import AppKit
import UsageCore
import WidgetKit

@MainActor
final class StatusController: NSObject {
    private let statusItem: NSStatusItem
    private let poller: UsagePoller
    private var timer: Timer?
    private var isRefreshing = false
    private var latestUsages: [ProviderAccountUsage] = []

    init(poller: UsagePoller) {
        self.poller = poller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
    }

    func start() {
        updateGrid(with: [])
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: poller.refreshSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func configureStatusItem() {
        statusItem.isVisible = true

        guard let button = statusItem.button else {
            return
        }

        button.title = ""
        button.image = nil
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .semibold)
        button.appearsDisabled = false
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        statusItem.menu = makeMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshMenuAction() {
        refresh()
    }

    @objc private func openConfigAction() {
        let path = ConfigurationLoader.defaultConfigPath
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        NSWorkspace.shared.open(directory)
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    private func refresh() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        DispatchQueue.global(qos: .utility).async { [poller] in
            let usages = poller.fetchAll()
            DispatchQueue.main.async {
                self.isRefreshing = false
                self.updateGrid(with: usages)
            }
        }
    }

    private func updateGrid(with usages: [ProviderAccountUsage]) {
        latestUsages = usages
        writeWidgetSnapshot(for: usages)

        if let button = statusItem.button {
            let image = StatusGridImageRenderer.image(for: usages, appearance: button.effectiveAppearance)
            button.title = ""
            button.image = image
            statusItem.length = image.size.width
            button.toolTip = tooltip(for: usages)
            button.setAccessibilityLabel(StatusGridImageRenderer.accessibilityLabel(for: usages))
        }
    }

    private func writeWidgetSnapshot(for usages: [ProviderAccountUsage]) {
        guard !usages.isEmpty else {
            return
        }

        guard (try? CodexUsageWidgetSnapshot(usages: usages).writeForWidgetExtension()) != nil else {
            return
        }

        WidgetCenter.shared.reloadTimelines(ofKind: CodexUsageWidgetSnapshot.widgetKind)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        if latestUsages.isEmpty {
            let loadingItem = NSMenuItem(title: "Loading usage...", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            menu.addItem(loadingItem)
        } else {
            for usage in latestUsages {
                let title = "\(usage.compactProviderLabel) \(usage.displayName)"
                let titleItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                titleItem.isEnabled = false
                menu.addItem(titleItem)

                addDisabledItem("\(usage.fiveHourDisplayText) resets \(formatReset(usage.fiveHourResetAt))", to: menu)
                addDisabledItem("\(usage.weeklyDisplayText) resets \(formatReset(usage.weeklyResetAt))", to: menu)
                if let planName = usage.planName {
                    addDisabledItem("Plan \(planName)", to: menu)
                }
                if let errorMessage = usage.errorMessage {
                    addDisabledItem("Last refresh error: \(errorMessage)", to: menu)
                }
                addDisabledItem("Updated \(formatTime(usage.updatedAt))", to: menu)
                menu.addItem(.separator())
            }
        }

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshMenuAction), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let configItem = NSMenuItem(title: "Open Config Folder", action: #selector(openConfigAction), keyEquivalent: ",")
        configItem.target = self
        menu.addItem(configItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func addDisabledItem(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func tooltip(for usages: [ProviderAccountUsage]) -> String {
        guard !usages.isEmpty else {
            return "AI usage"
        }

        return usages.map { usage in
            "\(usage.compactProviderLabel) \(usage.displayName): resets in \(usage.fiveHourResetCountdownText()), \(usage.fiveHourDisplayText), \(usage.weeklyDisplayText)"
        }.joined(separator: "\n")
    }

    private func formatReset(_ date: Date?) -> String {
        guard let date else {
            return "?"
        }
        return Self.resetFormatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
