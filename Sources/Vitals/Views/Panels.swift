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
            Divider()
            PanelFooter(module: module)
        }
        .padding(14)
        .frame(width: 300)
    }
}

private struct PanelFooter: View {
    let module: Module

    var body: some View {
        HStack(spacing: 12) {
            Button {
                let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            } label: {
                Label("Activity Monitor", systemImage: "waveform.path.ecg")
            }
            Spacer()
            Button { AppDelegate.shared?.showSettings() } label: { Image(systemName: "gearshape") }
                .help("Settings…")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Quit Vitals")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}

// MARK: - CPU

private struct CPUPanel: View {
    let store: Store

    var body: some View {
        let cpu = store.cpu
        PanelHeader(title: "CPU", symbol: Module.cpu.symbol, value: Format.percent(cpu.total),
                    detail: SystemInfo.current.chip.replacingOccurrences(of: "Apple ", with: ""))
        HistoryChart(series: [HistorySeries(name: "CPU", values: store.cpuHistory.values, color: Palette.user)],
                     maxValue: 1)
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                StatRow(label: "User", value: Format.percent(cpu.user), color: Palette.user)
                StatRow(label: "System", value: Format.percent(cpu.system), color: Palette.system)
                StatRow(label: "Idle", value: Format.percent(1 - cpu.total), color: Color.secondary.opacity(0.3))
            }
            VStack(spacing: 4) {
                StatRow(label: "Load 1m", value: String(format: "%.2f", cpu.load.0))
                StatRow(label: "5m", value: String(format: "%.2f", cpu.load.1))
                StatRow(label: "15m", value: String(format: "%.2f", cpu.load.2))
            }
        }
        PanelSection("Cores") {
            ForEach(store.clusters) { cluster in
                CoreGrid(name: cluster.name, loads: cluster.cores.map { $0 < cpu.cores.count ? cpu.cores[$0] : 0 })
            }
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
    let loads: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(name)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(loads.enumerated()), id: \.offset) { _, load in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1.5).fill(.quaternary)
                        RoundedRectangle(cornerRadius: 1.5).fill(Palette.load(load))
                            .frame(height: max(1, 22 * load))
                    }
                    .frame(height: 22)
                }
            }
        }
    }
}

// MARK: - GPU

private struct GPUPanel: View {
    let store: Store

    var body: some View {
        let gpu = store.gpu
        PanelHeader(title: "GPU", symbol: Module.gpu.symbol, value: Format.percent(gpu.utilization),
                    detail: store.gpuCores.map { "\($0) cores" })
        HistoryChart(series: [HistorySeries(name: "GPU", values: store.gpuHistory.values, color: Palette.gpu)],
                     maxValue: 1)
        VStack(spacing: 4) {
            StatRow(label: "Device", value: Format.percent(gpu.utilization), color: Palette.gpu)
            StatRow(label: "Renderer", value: Format.percent(gpu.renderer))
            StatRow(label: "Memory in use", value: Format.bytes(gpu.memoryInUse))
            if let temp = store.sensors.gpu {
                StatRow(label: "Temperature", value: Format.temperature(temp))
            }
            StatRow(label: "Model", value: store.gpuName)
        }
    }
}

// MARK: - Memory

private struct MemoryPanel: View {
    let store: Store

    var body: some View {
        let mem = store.memory
        let total = Double(max(mem.total, 1))
        PanelHeader(title: "Memory", symbol: Module.memory.symbol, value: Format.percent(mem.usedFraction),
                    detail: "\(Format.bytes(mem.used)) of \(Format.bytes(mem.total))")
        SegmentedBar(segments: [
            (Double(mem.app) / total, Palette.app),
            (Double(mem.wired) / total, Palette.wired),
            (Double(mem.compressed) / total, Palette.compressed),
            (Double(mem.cached) / total, Palette.cached),
        ])
        VStack(spacing: 4) {
            StatRow(label: "App", value: Format.bytes(mem.app), color: Palette.app)
            StatRow(label: "Wired", value: Format.bytes(mem.wired), color: Palette.wired)
            StatRow(label: "Compressed", value: Format.bytes(mem.compressed), color: Palette.compressed)
            StatRow(label: "Cached files", value: Format.bytes(mem.cached), color: Palette.cached)
            StatRow(label: "Swap used", value: mem.swapTotal > 0
                ? "\(Format.bytes(mem.swapUsed)) of \(Format.bytes(mem.swapTotal))" : "None")
            HStack {
                Text("Pressure").foregroundStyle(.secondary)
                Spacer()
                Text(mem.pressure.rawValue).foregroundStyle(Palette.pressure(mem.pressure))
            }
            .font(.system(size: 12))
        }
        HistoryChart(series: [HistorySeries(name: "Used", values: store.memoryHistory.values, color: Palette.app)],
                     maxValue: 1, height: 48)
        PanelSection("Top Processes") {
            ProcessList(processes: store.topProcesses(by: \.memory)) { Format.bytes($0.memory) }
        }
    }
}

// MARK: - Disk

private struct DiskPanel: View {
    let store: Store

    var body: some View {
        let disk = store.disk
        PanelHeader(title: "Disk", symbol: Module.disk.symbol,
                    value: disk.boot.map { Format.percent($0.usedFraction) } ?? "–",
                    detail: disk.boot.map { "\(Format.diskBytes($0.available)) free" })
        HistoryChart(series: [
            HistorySeries(name: "Read", values: store.readHistory.values, color: Palette.download),
            HistorySeries(name: "Write", values: store.writeHistory.values, color: Palette.upload),
        ])
        VStack(spacing: 4) {
            StatRow(label: "Read", value: Format.rate(disk.readRate), color: Palette.download)
            StatRow(label: "Write", value: Format.rate(disk.writeRate), color: Palette.upload)
        }
        PanelSection("Volumes") {
            ForEach(disk.volumes) { volume in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(volume.name).font(.system(size: 12))
                        Spacer()
                        Text("\(Format.diskBytes(volume.available)) free of \(Format.diskBytes(volume.total))")
                            .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    MeterBar(fraction: volume.usedFraction, color: Palette.load(volume.usedFraction))
                }
            }
        }
    }
}

// MARK: - Network

private struct NetworkPanel: View {
    let store: Store

    var body: some View {
        let net = store.network
        PanelHeader(title: "Network", symbol: Module.network.symbol, value: Format.rate(net.downRate + net.upRate))
        HistoryChart(series: [
            HistorySeries(name: "Download", values: store.downloadHistory.values, color: Palette.download),
            HistorySeries(name: "Upload", values: store.uploadHistory.values, color: Palette.upload),
        ])
        VStack(spacing: 4) {
            StatRow(label: "Download", value: Format.rate(net.downRate), color: Palette.download)
            StatRow(label: "Upload", value: Format.rate(net.upRate), color: Palette.upload)
            StatRow(label: "Peak download", value: Format.rate(store.downloadHistory.peak))
            StatRow(label: "Peak upload", value: Format.rate(store.uploadHistory.peak))
        }
        PanelSection("Interface") {
            StatRow(label: "Primary", value: net.interface ?? "Not connected")
            if let address = net.address {
                HStack {
                    StatRow(label: "Local IP", value: address)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(address, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).font(.system(size: 10)).help("Copy")
                }
            }
            StatRow(label: "Received since boot", value: Format.bytes(net.totalReceived))
            StatRow(label: "Sent since boot", value: Format.bytes(net.totalSent))
        }
    }
}

// MARK: - Sensors

private struct SensorsPanel: View {
    let store: Store

    var body: some View {
        let sensors = store.sensors
        PanelHeader(title: "Sensors", symbol: Module.sensors.symbol,
                    value: sensors.cpu.map { Format.temperature($0) } ?? "–", detail: "CPU", tint: heatColor(sensors.cpu))
        if !store.temperatureHistory.values.isEmpty {
            HistoryChart(series: [HistorySeries(name: "CPU", values: store.temperatureHistory.values, color: Palette.heat)],
                         maxValue: 110, height: 48)
        }
        PanelSection("Temperatures") {
            HStack {
                Spacer()
                Text("avg").frame(width: 44, alignment: .trailing)
                Text("max").frame(width: 44, alignment: .trailing)
            }
            .font(.system(size: 10)).foregroundStyle(.tertiary)
            ForEach(sensors.groups) { group in
                HStack {
                    Text(group.name).foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.temperature(group.average)).frame(width: 44, alignment: .trailing)
                    Text(Format.temperature(group.maximum)).frame(width: 44, alignment: .trailing)
                        .foregroundStyle(heatColor(group.maximum))
                }
                .font(.system(size: 12).monospacedDigit())
            }
        }
        if !sensors.fans.isEmpty {
            PanelSection("Fans") {
                ForEach(sensors.fans) { fan in
                    VStack(alignment: .leading, spacing: 3) {
                        StatRow(label: sensors.fans.count > 1 ? "Fan \(fan.index + 1)" : "Fan", value: Format.rpm(fan.rpm))
                        MeterBar(fraction: fan.fraction, color: .teal, height: 4)
                    }
                }
            }
        }
        if let power = sensors.systemPower {
            PanelSection("Power") {
                StatRow(label: "System total", value: Format.watts(power), color: Palette.power)
                HistoryChart(series: [HistorySeries(name: "Power", values: store.powerHistory.values, color: Palette.power)],
                             height: 40)
            }
        }
    }

    private func heatColor(_ celsius: Double?) -> Color {
        guard let celsius else { return .primary }
        return celsius >= 90 ? Palette.load(1) : celsius >= 75 ? Palette.load(0.7) : .primary
    }
}

// MARK: - Battery

private struct BatteryPanel: View {
    let store: Store

    var body: some View {
        if let battery = store.battery {
            PanelHeader(title: "Battery", symbol: Module.battery.symbol, value: Format.percent(battery.level),
                        tint: battery.level < 0.2 ? Palette.load(1) : .primary)
            MeterBar(fraction: battery.level, color: battery.isCharging ? Palette.gpu : Palette.load(1 - battery.level), height: 8)
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
        } else {
            PanelHeader(title: "Battery", symbol: Module.battery.symbol, value: "–")
            Text("This Mac doesn't have a battery.").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
