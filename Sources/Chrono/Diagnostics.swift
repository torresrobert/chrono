import AppKit
import SwiftUI

/// Headless modes for checking readings and layouts without clicking through the menu bar:
///   Chrono --dump            print current readings
///   Chrono --snapshot DIR [--scheme light|dark] [--range live|hour|day|week|month] [--history FILE]
///                            render every panel and the menu bar strip to PNGs
@MainActor
enum Diagnostics {
    static func dump() {
        let store = Store()
        store.refreshNow()
        Thread.sleep(forTimeInterval: 1)
        store.refreshNow()

        let cpu = store.cpu, mem = store.memory, net = store.network, disk = store.disk, s = store.sensors
        print("CPU      \(Format.percent(cpu.total)) (user \(Format.percent(cpu.user)), system \(Format.percent(cpu.system)))  load \(String(format: "%.2f %.2f %.2f", cpu.load.0, cpu.load.1, cpu.load.2))")
        for cluster in store.clusters {
            let loads = cluster.cores.map { Format.percent(cpu.cores[safe: $0] ?? 0) }
            print("  \(cluster.name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(loads.joined(separator: " "))")
        }
        print("GPU      \(Format.percent(store.gpu.utilization))  \(store.gpuName)  \(Format.bytes(store.gpu.memoryInUse)) in use")
        print("Memory   \(Format.bytes(mem.used)) / \(Format.bytes(mem.total))  app \(Format.bytes(mem.app)) wired \(Format.bytes(mem.wired)) compressed \(Format.bytes(mem.compressed)) cached \(Format.bytes(mem.cached))  swap \(Format.bytes(mem.swapUsed))  pressure \(mem.pressure.rawValue)")
        print("Network  ↓ \(Format.rate(net.downRate))  ↑ \(Format.rate(net.upRate))  \(net.interface ?? "-") \(net.address ?? "")")
        print("Disk     read \(Format.rate(disk.readRate))  write \(Format.rate(disk.writeRate))")
        for v in disk.volumes {
            print("  \(v.name): \(Format.diskBytes(v.available)) free of \(Format.diskBytes(v.total))")
        }
        for g in s.groups {
            print("Temp     \(g.name.padding(toLength: 9, withPad: " ", startingAt: 0)) avg \(Format.temperature(g.average, decimals: true)) max \(Format.temperature(g.maximum, decimals: true))  (\(g.count) sensors)")
        }
        for f in s.fans { print("Fan \(f.index)    \(Format.rpm(f.rpm)) (\(Format.rpm(f.minimum))–\(Format.rpm(f.maximum)))") }
        if let p = s.systemPower { print("Power    \(Format.watts(p))") }
        if let b = store.battery { print("Battery  \(Format.percent(b.level)) charging=\(b.isCharging)") } else { print("Battery  none") }
        print("Top CPU  " + store.topProcesses(by: \.cpu).map { "\($0.name) \(Format.percent($0.cpu))" }.joined(separator: ", "))
        print("Top MEM  " + store.topProcesses(by: \.memory).map { "\($0.name) \(Format.bytes($0.memory))" }.joined(separator: ", "))
    }

    static func snapshot(to directory: URL, dark: Bool, range: HistoryRange = .live, history: URL? = nil) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = Store(archive: HistoryArchive(file: history ?? HistoryArchive.defaultFile))
        store.chartRange = range
        for _ in 0..<12 {
            store.refreshNow()
            Thread.sleep(forTimeInterval: 0.5)
        }

        // Draw through a real NSHostingView in an offscreen window: ImageRenderer mis-resolves
        // dynamic colors (a translucent veil over everything), while the AppKit path matches the
        // live popover and also draws the footer's buttons.
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        for module in Module.allCases {
            let host = NSHostingView(rootView: PanelView(module: module, store: store).background(Theme.background))
            host.frame.size = host.fittingSize
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20000, y: 0), size: host.frame.size),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = appearance
            window.contentView = host
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: directory.appendingPathComponent("panel-\(module.rawValue)-\(dark ? "dark" : "light").png"))
            }
            window.orderOut(nil)
        }

        for labels in [true, false] {
            for (name, ink, background) in [("", MenuBarInk(colored: true, dark: true), Color(white: 0.16)),
                                            ("-light", MenuBarInk(colored: true, dark: false), Color(white: 0.93)),
                                            ("-mono", MenuBarInk.template, Color(white: 0.16))] {
                let strip = HStack(spacing: 10) {
                    ForEach(Module.allCases) { module in
                        if let image = MenuBarRenderer.image(for: module, store: store, showLabels: labels, ink: ink) {
                            if ink.colored {
                                Image(nsImage: image)
                            } else {
                                Image(nsImage: image).renderingMode(.template).foregroundStyle(.white)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(background)
                write(strip, to: directory.appendingPathComponent("menubar\(name)\(labels ? "" : "-nolabels").png"))
            }
        }
        print("Wrote snapshots to \(directory.path)")
    }

    private static func write(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
