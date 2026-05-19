import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let configuration = ConfigurationLoader.load()
        let poller = UsagePoller(configuration: configuration)
        let controller = StatusController(poller: poller)
        statusController = controller
        controller.start()
    }
}
