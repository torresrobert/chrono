import AppKit

let arguments = CommandLine.arguments

if arguments.contains("--dump") {
    MainActor.assumeIsolated { Diagnostics.dump() }
} else if let i = arguments.firstIndex(of: "--snapshot"), i + 1 < arguments.count {
    // Offscreen rendering only resolves one appearance correctly per process, so pick one.
    let scheme = arguments.firstIndex(of: "--scheme").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
    MainActor.assumeIsolated {
        Diagnostics.snapshot(to: URL(fileURLWithPath: arguments[i + 1]), dark: scheme != "light")
    }
} else {
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
