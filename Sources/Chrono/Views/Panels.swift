import AppKit
import SwiftUI

/// The popover content for one module.
struct PanelView: View {
    let module: Module
    let store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch module {
            case .cpu: CPUPanel(store: store)
            case .gpu: GPUPanel(store: store)
            case .memory: MemoryPanel(store: store)
            case .disk: DiskPanel(store: store)
            case .network: NetworkPanel(store: store)
            case .sensors: SensorsPanel(store: store)
            case .battery: BatteryPanel(store: store)
            }
            PanelFooter()
        }
        .padding(16)
        .frame(width: 312)
        .background(alignment: .top) {
            BrandedGradientBackground(tint: Theme.accent).frame(height: 180)
        }
        .tint(Theme.accent)
    }
}

private struct PanelFooter: View {
    var body: some View {
        VStack(spacing: 10) {
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 14) {
                Button {
                    let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                } label: {
                    Label("Activity Monitor", systemImage: "arrow.up.forward.app")
                }
                Spacer()
                Button { AppDelegate.shared?.showSettings() } label: { Image(systemName: "gearshape") }
                    .help("Settings…")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quit Chrono")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - CPU

private struct CPUPanel: View {
    let store: Store

    var body: some View {
        let cpu = store.cpu
        PanelHeader(title: "CPU", symbol: Module.cpu.symbol,
                    detail: SystemInfo.current.chip.replacingOccurrences(of: "Apple ", with: "")) {
            DialGauge(fraction: cpu.total, label: Format.percent(cpu.total))
        }
        MetricChart(store: store, series: [MetricSeries(metric: .cpu, name: "CPU", color: Series.primary)],
                    maxValue: 1, format: Format.percent)
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 4) {
                StatRow(label: "User", value: Format.percent(cpu.user), color: Series.primary)
                StatRow(label: "System", value: Format.percent(cpu.system), color: Series.secondary)
                StatRow(label: "Idle", value: Format.percent(1 - cpu.total), color: Series.neutral)
            }
            VStack(spacing: 4) {
                StatRow(label: "Load 1m", value: String(format: "%.2f", cpu.load.0))
                StatRow(label: "5m", value: String(format: "%.2f", cpu.load.1))
                StatRow(label: "15m", value: String(format: "%.2f", cpu.load.2))
            }
        }
        PanelSection("Cores") {
            VStack(spacing: 6) {
                ForEach(Array(store.clusters.enumerated()), id: \.element.id) { index, cluster in
                    CoreGrid(name: cluster.name, firstCore: cluster.cores.lowerBound,
                             loads: cluster.cores.map { cpu.cores[safe: $0] ?? 0 },
                             // Key for the menu bar's per-core bars, which tell clusters apart by color.
                             swatch: Settings.shared.cpuMenuBar == .cores && Settings.shared.menuBarStyle == .color
                                && store.clusters.count > 1 ? Series.cluster(index) : nil)
                }
            }
            .appCard(padding: 8)
        }
        PanelSection("Top Processes") {
            ProcessList(processes: store.topProcesses(by: \.cpu)) { Format.percent($0.cpu) }
        }
        if let boot = SystemInfo.bootDate {
            StatRow(label: "Uptime", value: Format.duration(since: boot))
        }
    }
}

private struct CoreGrid: View {
    let name: String
    let firstCore: Int
    let loads: [Double]
    var swatch: Color?

    /// The cluster's share of its own capacity (every logical core weighs the same).
    private var average: Double { loads.isEmpty ? 0 : loads.reduce(0, +) / Double(loads.count) }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    if let swatch { Circle().fill(swatch).frame(width: 6, height: 6) }
                    Text(name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                }
                HStack(spacing: 0) {
                    Text("\(loads.count) cores · ").foregroundStyle(Theme.textSecondary)
                    Text(Format.percent(average)).foregroundStyle(Theme.textPrimary).fontWeight(.semibold)
                }
                .font(.system(size: 9).monospacedDigit())
            }
            .frame(width: 84, alignment: .leading)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(loads.enumerated()), id: \.offset) { offset, load in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.border)
                        RoundedRectangle(cornerRadius: 2).fill(Theme.load(load))
                            .frame(height: max(1.5, 22 * load))
                    }
                    .frame(height: 22)
                    .contentShape(Rectangle())
                    .help("Core \(firstCore + offset) · \(Format.percent(load))")
                    .accessibilityElement()
                    .accessibilityLabel("\(name) core \(firstCore + offset), \(Format.percent(load))")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name) cores, \(Format.percent(average)) average")
    }
}

// MARK: - GPU

private struct GPUPanel: View {
    let store: Store

    var body: some View {
        let gpu = store.gpu
        PanelHeader(title: "GPU", symbol: Module.gpu.symbol,
                    detail: [store.gpuName.replacingOccurrences(of: "Apple ", with: ""), store.gpuCores.map { "\($0) cores" }]
                        .compactMap { $0 }.joined(separator: " · ")) {
            DialGauge(fraction: gpu.utilization, label: Format.percent(gpu.utilization))
        }
        MetricChart(store: store, series: [MetricSeries(metric: .gpu, name: "GPU", color: Series.primary)],
                    maxValue: 1, format: Format.percent)
        VStack(spacing: 4) {
            StatRow(label: "Busy", value: Format.percent(gpu.utilization), color: Series.primary)
            StatRow(label: "Renderer", value: Format.percent(gpu.renderer))
            // Busy time alone reads near 100% under any steady load; the clock shows how hard.
            if let maxClock = store.gpuMaxClock {
                StatRow(label: "Clock", value: gpu.clock.map {
                    "\(Format.megahertz($0)) · \(Format.percent($0 / maxClock)) of max"
                } ?? "Idle")
            }
            if let power = gpu.power {
                StatRow(label: "Power", value: Format.watts(power))
            }
            StatRow(label: "Memory in use", value: Format.bytes(gpu.memoryInUse))
            if let temp = store.sensors.gpu {
                StatRow(label: "Temperature", value: Format.temperature(temp), valueColor: Theme.temperature(temp))
            }
        }
    }
}

// MARK: - Memory

private struct MemoryPanel: View {
    let store: Store

    var body: some View {
        let mem = store.memory
        let total = Double(max(mem.total, 1))
        PanelHeader(title: "Memory", symbol: Module.memory.symbol,
                    detail: "\(Format.bytes(mem.used)) of \(Format.bytes(mem.total))") {
            DialGauge(fraction: mem.usedFraction, label: Format.percent(mem.usedFraction),
                      level: StatusLevel(pressure: mem.pressure))
        }
        VStack(alignment: .leading, spacing: 8) {
            SegmentedBar(segments: [
                (Double(mem.app) / total, Series.primary),
                (Double(mem.wired) / total, Series.secondary),
                (Double(mem.compressed) / total, Series.tertiary),
                (Double(mem.cached) / total, Series.neutral),
            ])
            VStack(spacing: 4) {
                StatRow(label: "App", value: Format.bytes(mem.app), color: Series.primary)
                StatRow(label: "Wired", value: Format.bytes(mem.wired), color: Series.secondary)
                StatRow(label: "Compressed", value: Format.bytes(mem.compressed), color: Series.tertiary)
                StatRow(label: "Cached files", value: Format.bytes(mem.cached), color: Series.neutral)
            }
        }
        .appCard()
        VStack(spacing: 4) {
            StatRow(label: "Pressure", value: mem.pressure.rawValue, valueColor: Theme.pressure(mem.pressure))
            StatRow(label: "Swap used", value: mem.swapTotal > 0
                ? "\(Format.bytes(mem.swapUsed)) of \(Format.bytes(mem.swapTotal))" : "None")
        }
        MetricChart(store: store, series: [MetricSeries(metric: .memory, name: "Used", color: Series.primary)],
                    maxValue: 1, height: 44, format: Format.percent)
        PanelSection("Top Processes") {
            ProcessList(processes: store.topProcesses(by: \.memory)) { Format.bytes($0.memory) }
        }
    }
}

extension Theme {
    static func pressure(_ p: MemoryPressure) -> Color {
        switch p {
        case .normal: positive
        case .warning: warning
        case .critical: negative
        }
    }
}

// MARK: - Disk

private struct DiskPanel: View {
    let store: Store

    var body: some View {
        let disk = store.disk
        PanelHeader(title: "Disk", symbol: Module.disk.symbol,
                    detail: disk.boot.map { "\(Format.diskBytes($0.available)) free" }) {
            if let boot = disk.boot {
                DialGauge(fraction: boot.usedFraction, label: Format.percent(boot.usedFraction))
            }
        }
        MetricChart(store: store, series: [
            MetricSeries(metric: .read, name: "Read", color: Series.tertiary),
            MetricSeries(metric: .write, name: "Write", color: Series.secondary),
        ], format: Format.rate)
        VStack(spacing: 4) {
            StatRow(label: "Read", value: Format.rate(disk.readRate), color: Series.tertiary)
            StatRow(label: "Write", value: Format.rate(disk.writeRate), color: Series.secondary)
        }
        PanelSection("Volumes") {
            VStack(spacing: 8) {
                ForEach(disk.volumes) { volume in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(volume.name).font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(Format.diskBytes(volume.available)) free of \(Format.diskBytes(volume.total))")
                                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary).monospacedDigit()
                        }
                        MeterBar(fraction: volume.usedFraction, color: Theme.load(volume.usedFraction))
                    }
                }
            }
            .appCard()
        }
    }
}

// MARK: - Network

private struct NetworkPanel: View {
    let store: Store

    var body: some View {
        let net = store.network
        PanelHeader(title: "Network", symbol: Module.network.symbol,
                    value: Format.rate(net.downRate + net.upRate), detail: net.interface.map { "via \($0)" })
        MetricChart(store: store, series: [
            MetricSeries(metric: .download, name: "Down", color: Series.tertiary),
            MetricSeries(metric: .upload, name: "Up", color: Series.secondary),
        ], format: Format.rate)
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 4) {
                StatRow(label: "Down", value: Format.rate(net.downRate), color: Series.tertiary)
                StatRow(label: "Up", value: Format.rate(net.upRate), color: Series.secondary)
            }
            VStack(spacing: 4) {
                StatRow(label: "Peak", value: Format.rate(store.downloadHistory.peak))
                StatRow(label: "Peak", value: Format.rate(store.uploadHistory.peak))
            }
        }
        PanelSection("Interface") {
            VStack(spacing: 4) {
                StatRow(label: "Primary", value: net.interface ?? "Not connected")
                if let address = net.address {
                    HStack(spacing: 6) {
                        StatRow(label: "Local IP", value: address)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(address, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless).font(.system(size: 10)).help("Copy IP address")
                    }
                }
                StatRow(label: "Received since boot", value: Format.bytes(net.totalReceived))
                StatRow(label: "Sent since boot", value: Format.bytes(net.totalSent))
            }
            .appCard()
        }
    }
}

// MARK: - Sensors

private struct SensorsPanel: View {
    let store: Store

    var body: some View {
        let sensors = store.sensors
        PanelHeader(title: "Sensors", symbol: Module.sensors.symbol, detail: "CPU temperature") {
            if let cpu = sensors.cpu {
                // Dial spans 20–110 °C with the redline at 90 °C (the throttling neighborhood).
                DialGauge(fraction: (cpu - 20) / 90, label: Format.temperature(cpu), redline: 70.0 / 90,
                          level: StatusLevel(celsius: cpu))
            } else {
                Readout(value: "–")
            }
        }
        if sensors.cpu != nil {
            MetricChart(store: store, series: [MetricSeries(metric: .temperature, name: "CPU", color: Series.heat)],
                        maxValue: 110, height: 44, format: { Format.temperature($0) })
        }
        PanelSection("Temperatures") {
            VStack(spacing: 4) {
                HStack {
                    Spacer()
                    Text("avg").frame(width: 44, alignment: .trailing)
                    Text("max").frame(width: 44, alignment: .trailing)
                }
                .font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                ForEach(sensors.groups) { group in
                    HStack {
                        Text(group.name).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(Format.temperature(group.average)).frame(width: 44, alignment: .trailing)
                        Text(Format.temperature(group.maximum)).frame(width: 44, alignment: .trailing)
                            .foregroundStyle(Theme.temperature(group.maximum))
                    }
                    .font(.system(size: 12).monospacedDigit())
                }
            }
            .appCard()
        }
        if !sensors.fans.isEmpty {
            PanelSection("Fans") {
                VStack(spacing: 8) {
                    ForEach(sensors.fans) { fan in
                        VStack(alignment: .leading, spacing: 4) {
                            StatRow(label: sensors.fans.count > 1 ? "Fan \(fan.index + 1)" : "Fan", value: Format.rpm(fan.rpm))
                            MeterBar(fraction: fan.fraction, color: Series.tertiary, height: 4)
                        }
                    }
                }
                .appCard()
            }
        }
        if let power = sensors.systemPower {
            PanelSection("Power") {
                StatRow(label: "System total", value: Format.watts(power), color: Series.power)
                MetricChart(store: store, series: [MetricSeries(metric: .power, name: "Power", color: Series.power)],
                            height: 36, picker: sensors.cpu == nil, format: Format.watts)
            }
        }
    }
}

// MARK: - Battery

private struct BatteryPanel: View {
    let store: Store

    var body: some View {
        if let battery = store.battery {
            PanelHeader(title: "Battery", symbol: Module.battery.symbol,
                        detail: battery.isCharging ? "Charging" : battery.isPluggedIn ? "On power adapter" : "On battery") {
                DialGauge(fraction: battery.level, label: Format.percent(battery.level), redline: 1,
                          level: StatusLevel(battery: battery))
            }
            VStack(spacing: 4) {
                StatRow(label: "Power source", value: battery.isPluggedIn ? "Power adapter" : "Battery")
                StatRow(label: "State", value: battery.isCharging ? "Charging" : battery.isPluggedIn ? "Not charging" : "Discharging")
                if let minutes = battery.minutesRemaining {
                    StatRow(label: battery.isCharging ? "Until full" : "Remaining", value: Format.minutes(minutes))
                }
                if let health = battery.health {
                    StatRow(label: "Health", value: health)
                }
            }
            .appCard()
        } else {
            PanelHeader(title: "Battery", symbol: Module.battery.symbol, value: "–")
            Text("This Mac doesn't have a battery.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        }
    }
}
