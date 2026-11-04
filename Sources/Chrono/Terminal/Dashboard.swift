import Darwin
import Foundation

/// Dark-appearance values of the app's series colors (`Series`), for the terminal.
enum TerminalPalette {
    static let blue: UInt = 0x60A5FA
    static let violet: UInt = 0xA78BFA
    static let cyan: UInt = 0x22D3EE
    static let heat: UInt = 0xFB923C
    static let power: UInt = 0xFACC15

    static func cluster(_ index: Int) -> UInt { [0xF472B6, 0x2DD4BF, 0xA3E635][index % 3] }  // pink, teal, lime

    /// The color at reduced brightness, for the peak shading behind a chart's average.
    static func dimmed(_ color: UInt, by factor: Double = 0.4) -> UInt {
        [16, 8, 0].reduce(0) { result, shift in
            result | UInt((Double((color >> UInt(shift)) & 0xff) * factor).rounded()) << UInt(shift)
        }
    }

    static func series(_ metric: Metric) -> UInt {
        switch metric {
        case .cpu: blue
        case .gpu, .upload, .write: violet
        case .memory, .download, .read: cyan
        case .temperature: heat
        case .power: power
        case .load: blue
        case .swapOut: violet
        case .pressure: cyan
        case .thermal: heat
        }
    }
}

/// The terminal view's screen, drawn from the same `Store` as the menu bar panels:
/// a summary row per module, a history chart for one metric, and the busiest processes.
@MainActor
struct Dashboard {
    let store: Store
    let interval: Double
    var metric: Metric = .cpu
    var range: HistoryRange = .live
    var sortByMemory = false

    private static let labelWidth = 10

    /// Metrics the chart can show on this Mac.
    var metrics: [Metric] {
        var list: [Metric] = [.cpu, .gpu, .memory, .download, .upload, .read, .write]
        if store.sensors.cpu != nil { list.append(.temperature) }
        if store.sensors.systemPower != nil { list.append(.power) }
        return list
    }

    mutating func cycleMetric(by step: Int) {
        let list = metrics
        let index = list.firstIndex(of: metric) ?? 0
        metric = list[(index + step + list.count) % list.count]
    }

    mutating func cycleRange() {
        let all = HistoryRange.allCases
        range = all[((all.firstIndex(of: range) ?? 0) + 1) % all.count]
    }

    func lines(width: Int, height: Int) -> [Line] {
        var lines = [header(width: width), Line()] + summary(width: width)
        // Left for the chart and process list, after a blank line and the footer.
        let remaining = height - lines.count - 2
        if remaining >= 4 {
            let chartRows = remaining < 10 ? min(8, remaining - 2) : max(3, min(8, (remaining - 4) * 2 / 5))
            lines.append(Line())
            lines += chart(width: width, rows: chartRows)
            let processRows = remaining - 4 - chartRows
            if processRows > 0 {
                lines.append(Line())
                lines += processes(width: width, rows: processRows)
            }
        }
        while lines.count < height - 1 { lines.append(Line()) }
        return Array(lines.prefix(max(0, height - 1))) + [footer()]
    }

    // MARK: - Sections

    private var accent: Style { Style(color: Settings.shared.accent.darkHex, bold: true) }

    private func header(width: Int) -> Line {
        var line = Line(" Chrono", accent)
        line.add("  " + Self.hostName, .strong)
        var detail = [SystemInfo.current.chip]
        if let boot = SystemInfo.bootDate { detail.append("up " + Format.duration(since: boot)) }
        line.add("  " + detail.joined(separator: " · "), .muted)
        line.trailing(Date().formatted(date: .omitted, time: .shortened), .muted, at: width - 2)
        return line
    }

    private func summary(width: Int) -> [Line] {
        let meterWidth = max(8, min(24, (width - 50) / 2))
        let detailColumn = Self.labelWidth + 5 + 2 + meterWidth + 2
        var lines: [Line] = []

        let cpu = store.cpu
        var line = label("CPU")
        gauge(&line, cpu.total, level: StatusLevel(load: cpu.total), width: meterWidth)
        line.add("user \(Format.percent(cpu.user)) · system \(Format.percent(cpu.system)) · load "
                 + String(format: "%.2f %.2f %.2f", cpu.load.0, cpu.load.1, cpu.load.2), .muted)
        lines.append(line)

        if !store.clusters.isEmpty {
            var line = label("")
            for (index, cluster) in store.clusters.enumerated() {
                let loads = cluster.cores.map { cpu.cores[safe: $0] ?? 0 }
                let average = loads.isEmpty ? 0 : loads.reduce(0, +) / Double(loads.count)
                if index > 0 { line.add("   ") }
                line.add(cluster.name + " ", .muted)
                line.add(TerminalChart.sparkline(loads), Style(color: TerminalPalette.cluster(index)))
                line.add(" " + Format.percent(average))
            }
            lines.append(line)
        }

        let gpu = store.gpu
        line = label("GPU")
        gauge(&line, gpu.utilization, level: StatusLevel(load: gpu.utilization), width: meterWidth)
        var gpuDetail = [store.gpuName]
        if let cores = store.gpuCores { gpuDetail.append("\(cores) cores") }
        if let clock = gpu.clock, let maxClock = store.gpuMaxClock {
            gpuDetail.append("\(Format.megahertz(clock)) of \(Format.megahertz(maxClock))")
        }
        if let power = gpu.power { gpuDetail.append(Format.watts(power)) }
        gpuDetail.append("\(Format.bytes(gpu.memoryInUse)) in use")
        line.add(gpuDetail.joined(separator: " · "), .muted)
        lines.append(line)

        let memory = store.memory
        let pressure = StatusLevel(pressure: memory.pressure)
        line = label("Memory")
        gauge(&line, memory.usedFraction, level: pressure, width: meterWidth)
        line.add("\(Format.bytes(memory.used)) of \(Format.bytes(memory.total)) · swap \(Format.bytes(memory.swapUsed)) · ",
                 .muted)
        line.add(memory.pressure.rawValue.lowercased() + " pressure", pressure == .normal ? .muted : .status(pressure))
        lines.append(line)

        let disk = store.disk
        line = label("Disk")
        if let boot = disk.boot {
            gauge(&line, boot.usedFraction, level: StatusLevel(load: boot.usedFraction), width: meterWidth)
        } else {
            line.pad(to: detailColumn)
        }
        rate(&line, "read ", disk.readRate)
        rate(&line, "  write ", disk.writeRate)
        if let boot = disk.boot { line.add(" · \(Format.diskBytes(boot.available)) free on \(boot.name)", .muted) }
        lines.append(line)

        let network = store.network
        line = label("Network")
        rate(&line, "↓ ", network.downRate, color: TerminalPalette.cyan)
        rate(&line, "  ↑ ", network.upRate, color: TerminalPalette.violet)
        let route = [network.interface, network.address].compactMap { $0 }
        if !route.isEmpty {
            line.add("  ")
            line.pad(to: detailColumn)
            line.add(route.joined(separator: " · "), .muted)
        }
        lines.append(line)

        let sensors = store.sensors
        if !sensors.groups.isEmpty || sensors.systemPower != nil {
            line = label("Sensors")
            var items: [(String, String, Style)] = sensors.groups.map {
                ($0.name + " ", Format.temperature($0.average), .alert(StatusLevel(celsius: $0.average)))
            }
            if let power = sensors.systemPower { items.insert(("", Format.watts(power), .plain), at: min(2, items.count)) }
            if !sensors.fans.isEmpty {
                let speeds = sensors.fans.map { Int($0.rpm.rounded()).formatted() }.joined(separator: " · ")
                items.insert((sensors.fans.count > 1 ? "fans " : "fan ", speeds + " rpm", .plain), at: min(3, items.count))
            }
            // CPU, GPU, power and fans first; other sensor groups as far as the width allows.
            for (index, item) in items.enumerated() {
                let separator = index > 0 ? " · " : ""
                guard line.width + separator.count + item.0.count + item.1.count < width - 2 else { break }
                line.add(separator, .muted)
                line.add(item.0, .muted)
                line.add(item.1, item.2)
            }
            lines.append(line)
        }

        if let battery = store.battery {
            let level = StatusLevel(battery: battery)
            line = label("Battery")
            gauge(&line, battery.level, level: level, width: meterWidth)
            var state = battery.isCharging ? "charging" : battery.isPluggedIn ? "plugged in" : "on battery"
            if let minutes = battery.minutesRemaining, minutes > 0 {
                state += " · \(Format.minutes(minutes)) \(battery.isCharging ? "to full" : "left")"
            }
            line.add(state, .muted)
            lines.append(line)
        }
        return lines
    }

    private func chart(width: Int, rows: Int) -> [Line] {
        let count = max(1, width - 3) * 2
        let raw: [Double?], peaks: [Double?], average: Double, peak: Double, span: TimeInterval
        if range == .live {
            let values = store.liveHistory(metric).values
            span = Double(History.capacity) * interval
            raw = TerminalChart.columns(live: values, capacity: History.capacity, count: count)
            peaks = raw
            average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
            peak = values.max() ?? 0
        } else {
            let now = Date()
            span = TimeInterval(range.span ?? 0)
            let buckets = store.archive.series(metric, range: range, now: now)
            let start = now.addingTimeInterval(-span)
            raw = TerminalChart.columns(buckets, width: range.pointWidth, from: start, to: now, count: count)
            peaks = TerminalChart.columns(buckets, \.peak, width: range.pointWidth, from: start, to: now, count: count)
            let samples = buckets.reduce(0) { $0 + $1.count }
            average = samples > 0 ? buckets.reduce(0) { $0 + $1.sum } / Double(samples) : 0
            peak = buckets.map(\.peak).max() ?? 0
        }
        let hasData = raw.contains { $0 != nil }
        let upper = [.cpu, .gpu, .memory].contains(metric) ? 1 : max(peak * 1.15, 1)

        var header = Line(" " + title(metric), .strong)
        header.add(" · " + (range == .live ? "Live" : range.title), .muted)
        let stats = hasData ? "avg \(format(average, metric)) · peak \(format(peak, metric))" : ""
        let rule = width - 3 - header.width - stats.count - (stats.isEmpty ? 0 : 1)
        if rule > 0 { header.add(" " + String(repeating: "─", count: rule), .faint) }
        if !stats.isEmpty { header.add(" " + stats, .muted) }

        var lines = [header]
        if hasData {
            // Like the app's charts: the average solid, the peaks above it dimmed.
            let averageDots = TerminalChart.dots(raw.map { $0.map { $0 / upper } }, rows: rows)
            let peakDots = TerminalChart.dots(peaks.map { $0.map { $0 / upper } }, rows: rows)
            let color = TerminalPalette.series(metric)
            let solid = Style(color: color), dim = Style(color: TerminalPalette.dimmed(color))
            for (averageRow, peakRow) in zip(averageDots, peakDots) {
                var line = Line(" ")
                var run = String.UnicodeScalarView(), runIsSolid = true
                for (average, peak) in zip(averageRow, peakRow) {
                    let isSolid = average != 0 || peak == 0
                    if isSolid != runIsSolid, !run.isEmpty {
                        line.add(String(run), runIsSolid ? solid : dim)
                        run = String.UnicodeScalarView()
                    }
                    runIsSolid = isSolid
                    run.append(TerminalChart.character(average | peak))
                }
                line.add(String(run), runIsSolid ? solid : dim)
                lines.append(line)
            }
        } else {
            for row in 0..<rows {
                lines.append(row == rows / 2 ? Line(" Collecting history. Check back in a few minutes.", .muted) : Line())
            }
        }
        var axis = Line(" " + Self.spanText(span) + " ago", .faint)
        axis.trailing("now", .faint, at: width - 2)
        lines.append(axis)
        return lines
    }

    private func processes(width: Int, rows: Int) -> [Line] {
        let memoryColumn = width - 2, cpuColumn = memoryColumn - 11
        var header = Line(" Process", .muted)
        header.trailing("CPU", sortByMemory ? .muted : .strong, at: cpuColumn)
        header.trailing("Memory", sortByMemory ? .strong : .muted, at: memoryColumn)

        let top = sortByMemory ? store.topProcesses(by: \.memory, limit: rows) : store.topProcesses(by: \.cpu, limit: rows)
        return [header] + top.map { process in
            let badge = process.isSimulator ? " Simulator" : ""
            var line = Line(" " + Self.fit(process.name, width: cpuColumn - 10 - badge.count))
            if !badge.isEmpty { line.add(badge, .faint) }
            line.trailing(Format.percent(process.cpu), at: cpuColumn)
            line.trailing(Format.bytes(process.memory), .muted, at: memoryColumn)
            return line
        }
    }

    private func footer() -> Line {
        var line = Line(" 1–5 ", .strong)
        for option in HistoryRange.allCases {
            line.add(option.title, option == range ? accent : .muted)
            line.add(" ")
        }
        for (key, action) in [("tab", "chart"), ("c/m", "sort"), ("q", "quit")] {
            line.add("  " + key + " ", .strong)
            line.add(action, .muted)
        }
        return line
    }

    // MARK: - Pieces

    private func label(_ text: String) -> Line {
        var line = Line(" " + text, .strong)
        line.pad(to: Self.labelWidth)
        return line
    }

    private func gauge(_ line: inout Line, _ fraction: Double, level: StatusLevel, width: Int) {
        let value = Format.percent(fraction)
        line.add(String(repeating: " ", count: max(0, 5 - value.count)) + value, .alert(level))
        line.add("  ")
        let meter = TerminalChart.meter(fraction, width: width)
        line.add(meter.filled, .status(level))
        line.add(meter.track, .faint)
        line.add("  ")
    }

    private func rate(_ line: inout Line, _ label: String, _ value: Double, color: UInt? = nil) {
        line.add(label, color.map { Style(color: $0) } ?? .muted)
        line.add(Format.rate(value))
    }

    private func title(_ metric: Metric) -> String {
        switch metric {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .download: "Network ↓"
        case .upload: "Network ↑"
        case .read: "Disk read"
        case .write: "Disk write"
        case .temperature: "CPU temperature"
        case .power: "Power"
        case .load: "Load average"
        case .swapOut: "Swap out"
        case .pressure: "Memory pressure"
        case .thermal: "Thermal state"
        }
    }

    private func format(_ value: Double, _ metric: Metric) -> String {
        switch metric {
        case .cpu, .gpu, .memory: Format.percent(value)
        case .download, .upload, .read, .write: Format.rate(value)
        case .temperature: Format.temperature(value)
        case .power: Format.watts(value)
        case .load, .pressure, .thermal: String(format: "%.1f", value)
        case .swapOut: Format.rate(value)
        }
    }

    private static func spanText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(1, minutes)) min" }
        if minutes < 48 * 60 { return minutes == 60 ? "1 hour" : "\(minutes / 60) hours" }
        return "\(minutes / 1440) days"
    }

    nonisolated static func fit(_ text: String, width: Int) -> String {
        guard text.count > width else { return text }
        return width > 1 ? String(text.prefix(width - 1)) + "…" : ""
    }

    private static let hostName: String = {
        var buffer = [CChar](repeating: 0, count: 256)
        guard gethostname(&buffer, buffer.count) == 0 else { return "Mac" }
        let name = String(cString: buffer)
        return name.hasSuffix(".local") ? String(name.dropLast(6)) : name
    }()
}
