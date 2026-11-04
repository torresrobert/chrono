import Foundation

/// `chrono --report`: turns saved history and spikes into a plain-text answer to "is this Mac
/// underused, well used or pushed too far?". Pure formatting; it never samples or writes.
@MainActor
enum Report {
    enum State: String, CaseIterable { case idle = "Idle", busy = "Busy", maxed = "Maxed", overloaded = "Overloaded" }
    enum Reason: String, CaseIterable {
        case load = "work waiting", pressure = "memory pressure", swap = "heavy swapping", heat = "heat"
    }

    private static let window = 900  // seconds in one quarter-hour bucket
    private static let dayRows = 14
    private static let spikeRows = 15

    /// One 15-minute window's state, and why if it's overloaded. Missing buckets count as "not measured", never as a problem.
    static func classify(cpu: Bucket, gpu: Bucket?, memory: Bucket?, load: Bucket?, swapOut: Bucket?,
                         pressure: Bucket?, thermal: Bucket?, cores: Int) -> (state: State, reasons: [Reason]) {
        var reasons: [Reason] = []
        if let load, load.average >= Double(2 * cores) { reasons.append(.load) }
        if let pressure, pressure.average >= 0.25 || pressure.peak >= 2 { reasons.append(.pressure) }
        if let swapOut, swapOut.average >= 5_000_000 { reasons.append(.swap) }
        if let thermal, thermal.peak >= 2 { reasons.append(.heat) }
        if !reasons.isEmpty { return (.overloaded, reasons) }

        let gpuAverage = gpu?.average ?? 0
        if cpu.average >= 0.9 || gpuAverage >= 0.9 || (memory?.average ?? 0) >= 0.9 { return (.maxed, []) }
        if cpu.average < 0.25, gpuAverage < 0.25 { return (.idle, []) }
        return (.busy, [])
    }

    /// "under 1m", "45m", "2h 45m", "3d 4h" (largest two units; no zero second unit: "2h", "3d").
    static func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 1 { return "under 1m" }
        let days = minutes / 1440, hours = minutes % 1440 / 60, mins = minutes % 60
        func pair(_ big: Int, _ bigUnit: String, _ small: Int, _ smallUnit: String) -> String {
            small == 0 ? "\(big)\(bigUnit)" : "\(big)\(bigUnit) \(small)\(smallUnit)"
        }
        if days > 0 { return pair(days, "d", hours, "h") }
        if hours > 0 { return pair(hours, "h", mins, "m") }
        return "\(mins)m"
    }

    // MARK: - Text

    private struct Window {
        var start: Int
        var cpu: Bucket
        var gpu: Bucket?
        var memory: Bucket?
        var measured: Bool
        var state: State
        var reasons: [Reason]
    }

    static func text(archive: HistoryArchive, spikes: [Spike], spikesEnabled: Bool, now: Date, days: Int,
                     cores: Int, calendar: Calendar = .current) -> String {
        let since = Int(now.timeIntervalSince1970) - days * 86_400
        func buckets(_ metric: Metric) -> [Bucket] {
            archive.metrics[metric]?.quarterHours.buckets(since: since) ?? []
        }
        func lookup(_ metric: Metric) -> [Int: Bucket] {
            Dictionary(buckets(metric).map { ($0.start, $0) }, uniquingKeysWith: { first, _ in first })
        }
        let cpuBuckets = buckets(.cpu)
        guard !cpuBuckets.isEmpty else {
            return "No history yet. Chrono records while the menu bar app is running."
        }
        let gpu = lookup(.gpu), memory = lookup(.memory), load = lookup(.load), swapOut = lookup(.swapOut)
        let pressure = lookup(.pressure), thermal = lookup(.thermal)

        let windows: [Window] = cpuBuckets.map { cpu in
            let start = cpu.start
            // Without a load bucket the window predates the overload signals, so it can't be judged on them.
            let measured = load[start] != nil
            let result = classify(cpu: cpu, gpu: gpu[start], memory: memory[start], load: load[start],
                                  swapOut: measured ? swapOut[start] : nil,
                                  pressure: measured ? pressure[start] : nil,
                                  thermal: measured ? thermal[start] : nil, cores: cores)
            return Window(start: start, cpu: cpu, gpu: gpu[start], memory: memory[start], measured: measured,
                          state: result.state, reasons: result.reasons)
        }

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.setLocalizedDateFormatFromTemplate("MMMd")
        func day(_ start: Int) -> String { dayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(start))) }

        var sections: [String] = []
        let total = windows.count
        let measuredCount = windows.filter(\.measured).count
        let counts = Dictionary(grouping: windows, by: \.state).mapValues(\.count)

        sections.append("Chrono report: last " + (days == 1 ? "1 day" : "\(days) days") + "\n"
            + "Recorded \(day(windows[0].start)) to \(day(windows[total - 1].start)) "
            + "(\(String(format: "%.1f", Double(total * window) / 86_400)) days)")

        // Verdict
        let overloaded = counts[.overloaded] ?? 0
        let ofTime = measuredCount < total ? "of the measured time" : "of the time"
        let overloadShare = measuredCount > 0 ? Double(overloaded) / Double(measuredCount) : 0
        let idleShare = Double(counts[.idle] ?? 0) / Double(total)
        let usedShare = Double((counts[.busy] ?? 0) + (counts[.maxed] ?? 0)) / Double(total)
        let verdict: String
        if measuredCount > 0, overloadShare >= 0.10 {
            verdict = "Pushed too far: overloaded \(Format.percent(overloadShare)) \(ofTime)."
        } else if measuredCount > 0, overloadShare >= 0.02 {
            verdict = "Busy, with some overload: overloaded \(Format.percent(overloadShare)) \(ofTime)."
        } else if idleShare >= 0.75 {
            verdict = "Plenty of headroom: idle \(Format.percent(idleShare)) of the time."
        } else {
            verdict = "Well used: busy or maxed \(Format.percent(usedShare)) of the time."
                + (measuredCount > 0 ? " Rarely overloaded." : "")
        }
        sections.append(verdict)

        // Time spent
        var spent = ["Time spent"]
        for state in State.allCases {
            let count = counts[state] ?? 0
            var line = "  " + pad(state.rawValue, 10) + "  " + padLeft(Format.percent(Double(count) / Double(total)), 4)
                + "   " + (count == 0 ? "-" : duration(count * window))
            if state == .overloaded {
                let reasons = Reason.allCases.compactMap { reason -> String? in
                    let n = windows.filter { $0.reasons.contains(reason) }.count
                    return n > 0 ? "\(reason.rawValue) \(duration(n * window))" : nil
                }
                if !reasons.isEmpty { line += "  (" + reasons.joined(separator: ", ") + ")" }
            }
            spent.append(line)
        }
        sections.append(spent.joined(separator: "\n"))

        // Averages and peaks
        var rows: [(label: String, average: String, peak: String, extra: String)] = []
        func addRow(_ label: String, _ metric: Metric, _ average: (Double) -> String, _ peak: (Double) -> String,
                    extra: String = "") {
            let list = buckets(metric)
            guard !list.isEmpty else { return }
            let mean = list.map(\.average).reduce(0, +) / Double(list.count)
            rows.append((label, average(mean), peak(list.map(\.peak).max() ?? 0), extra))
        }
        addRow("CPU", .cpu, Format.percent, Format.percent)
        addRow("GPU", .gpu, Format.percent, Format.percent)
        addRow("Memory", .memory, Format.percent, Format.percent)
        addRow("Load", .load, { String(format: "%.1f", $0) }, { String(format: "%.0f", $0) }, extra: "   (\(cores) cores)")
        addRow("Swap out", .swapOut, Format.rate, Format.rate)
        addRow("Temperature", .temperature, { Format.temperature($0) }, { Format.temperature($0) })
        addRow("Power", .power, Format.watts, Format.watts)
        let labelWidth = rows.map(\.label.count).max() ?? 0
        let averageWidth = max("Average".count, rows.map(\.average.count).max() ?? 0)
        let peakWidth = max("Peak".count, rows.map(\.peak.count).max() ?? 0)
        func tableLine(_ label: String, _ average: String, _ peak: String, _ extra: String = "") -> String {
            "  " + pad(label, labelWidth) + "  " + padLeft(average, averageWidth) + "  " + padLeft(peak, peakWidth) + extra
        }
        var table = [tableLine("", "Average", "Peak")]
        table += rows.map { tableLine($0.label, $0.average, $0.peak, $0.extra) }
        var highest: [String] = []
        if let peak = buckets(.pressure).map(\.peak).max() {
            let names = ["Normal", "Warning", "Critical"]
            highest.append("Highest memory pressure: \(names[min(max(Int(peak.rounded()), 0), 2)]).")
        }
        if let peak = buckets(.thermal).map(\.peak).max() {
            let names = ["Nominal", "Fair", "Serious", "Critical"]
            highest.append("Highest thermal state: \(names[min(max(Int(peak.rounded()), 0), 3)]).")
        }
        if !highest.isEmpty { table.append(highest.joined(separator: " ")) }
        sections.append(table.joined(separator: "\n"))

        // Signals note
        if measuredCount == 0 {
            sections.append("Overload signals haven't been recorded yet, so this time can only show as Idle, Busy or Maxed.")
        } else if measuredCount < total, let first = windows.first(where: \.measured) {
            sections.append("Overload signals started \(day(first.start)), so earlier time can only show as Idle, Busy or Maxed.")
        }

        sections.append(byDay(windows, calendar: calendar, label: day))
        sections.append(spikeSection(spikes, enabled: spikesEnabled, since: since, calendar: calendar))
        return sections.joined(separator: "\n\n")
    }

    // MARK: - By day

    private static func byDay(_ windows: [Window], calendar: Calendar, label: (Int) -> String) -> String {
        // Local days via the calendar, so DST days (23 or 25 hours) group correctly.
        let groups = Dictionary(grouping: windows) { calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.start))) }
        let allDays = groups.keys.sorted()
        let shown = allDays.suffix(dayRows)
        func mean(_ values: [Double]) -> String { values.isEmpty ? "-" : Format.percent(values.reduce(0, +) / Double(values.count)) }
        func span(_ count: Int) -> String { count == 0 ? "-" : duration(count * window) }

        let rows = shown.map { date -> (String, String, String, String, String, String) in
            let list = groups[date] ?? []
            return (label(Int(date.timeIntervalSince1970)),
                    mean(list.map(\.cpu.average)), mean(list.compactMap { $0.gpu?.average }),
                    mean(list.compactMap { $0.memory?.average }),
                    span(list.filter { $0.state == .maxed }.count), span(list.filter { $0.state == .overloaded }.count))
        }
        let dateWidth = rows.map(\.0.count).max() ?? 0
        let maxedWidth = rows.map(\.4.count).max() ?? 0
        var lines = [allDays.count > dayRows ? "By day (last \(dayRows))" : "By day"]
        for r in rows {
            lines.append("  " + pad(r.0, dateWidth) + "    CPU " + padLeft(r.1, 4) + "   GPU " + padLeft(r.2, 4)
                + "   Memory " + padLeft(r.3, 4) + "   Maxed " + pad(r.4, maxedWidth) + "   Overloaded " + r.5)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Spikes

    private static func spikeSection(_ all: [Spike], enabled: Bool, since: Int, calendar: Calendar) -> String {
        guard enabled else { return "Spikes: process names are off in Settings" }
        let inRange = all.filter { $0.end >= since }.sorted { $0.end > $1.end }
        // "Recorded" because the log only knows about spikes since it started, unlike the charts above.
        guard !inRange.isEmpty else { return "Spikes: none recorded" }
        let shown = Array(inRange.prefix(spikeRows))

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.setLocalizedDateFormatFromTemplate("MMMd")
        let clock = DateFormatter()
        clock.calendar = calendar
        clock.timeZone = calendar.timeZone
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "HH:mm"

        let rows = shown.map { spike -> (time: String, name: String, peak: String, length: String, who: String) in
            let start = Date(timeIntervalSince1970: TimeInterval(spike.start))
            let end = Date(timeIntervalSince1970: TimeInterval(spike.end))
            let time = calendar.isDate(start, inSameDayAs: end)
                ? "\(dayFormatter.string(from: start)) \(clock.string(from: start))–\(clock.string(from: end))"
                : "\(dayFormatter.string(from: start)) \(clock.string(from: start))–\(dayFormatter.string(from: end)) \(clock.string(from: end))"
            return (time, name(spike.metric), Format.percent(spike.peak), duration(spike.end - spike.start), who(spike))
        }
        let timeWidth = rows.map(\.time.count).max() ?? 0
        let lengthWidth = rows.map(\.length.count).max() ?? 0

        var lines = [inRange.count > shown.count ? "Spikes (\(shown.count) most recent of \(inRange.count))" : "Spikes (\(inRange.count))"]
        for r in rows {
            lines.append("  " + pad(r.time, timeWidth) + "  " + pad(r.name, 6) + " " + padLeft(r.peak, 4) + "  "
                + pad(r.length, lengthWidth) + "   " + r.who)
        }
        if shown.contains(where: { $0.metric == .gpu }) {
            lines.append("Per-process GPU use isn't available, so GPU spikes list the largest processes by memory.")
        }
        lines.append("Only your own processes can be named.")
        return lines.joined(separator: "\n")
    }

    private static func name(_ metric: SpikeMetric) -> String {
        switch metric {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        }
    }

    private static func who(_ spike: Spike) -> String {
        let byCPU = spike.metric == .cpu
        let ranked = spike.processes
            .filter { byCPU ? $0.cpu > 0 : $0.memory > 0 }
            .sorted { a, b in
                if byCPU { return a.cpu != b.cpu ? a.cpu > b.cpu : a.name < b.name }
                return a.memory != b.memory ? a.memory > b.memory : a.name < b.name
            }
            .prefix(3)
        guard !ranked.isEmpty else { return "no processes captured" }
        return ranked.map { p in
            if byCPU {
                let cores = String(format: "%.1f", p.cpu)
                return "\(p.name) \(cores) \(cores == "1.0" ? "core" : "cores")"
            }
            return "\(p.name) \(Format.bytes(p.memory))"
        }.joined(separator: ", ")
    }

    private static func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }

    private static func padLeft(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
    }
}
