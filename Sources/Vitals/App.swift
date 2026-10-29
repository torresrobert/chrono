import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?

    private let store = Store()
    private let settings = Settings.shared
    private var statusBar: StatusBarController?
    private var settingsWindow: NSWindow?
    private var interval: Double = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        statusBar = StatusBarController(store: store, settings: settings)
        store.onUpdate = { [weak self] in self?.statusBar?.render() }
        settings.onChange = { [weak self] in self?.settingsChanged() }
        interval = settings.interval
        store.start(interval: interval)

        if CommandLine.arguments.contains("--selftest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
                for line in statusBar?.selfTest() ?? [] { print(line) }
                exit(0)
            }
        }
    }

    private func settingsChanged() {
        statusBar?.sync()
        if settings.interval != interval {
            interval = settings.interval
            store.start(interval: interval)
        }
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings, store: store)))
            window.title = "Vitals Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
