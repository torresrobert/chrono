import AppKit

let arguments = CommandLine.arguments

if arguments.contains("--dump") {
    MainActor.assumeIsolated { Diagnostics.dump() }
} else if let i = arguments.firstIndex(of: "--snapshot"), i + 1 < arguments.count {
    MainActor.assumeIsolated { Diagnostics.snapshot(to: URL(fileURLWithPath: arguments[i + 1])) }
} else {
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
