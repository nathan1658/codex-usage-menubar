import AppKit

if CommandLine.arguments.contains("--print-once") {
    let configuration = ConfigurationLoader.load()
    let usages = UsagePoller(configuration: configuration).fetchAll()
    for usage in usages {
        let errorSuffix = usage.errorMessage.map { " error=\($0)" } ?? ""
        print("\(usage.compactProviderLabel) \(usage.displayName): \(usage.fiveHourDisplayText) | \(usage.weeklyDisplayText)\(errorSuffix)")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
