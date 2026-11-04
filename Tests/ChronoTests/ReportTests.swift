import Foundation
import Testing
@testable import Chrono

private let ny: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    ny.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private func b(_ average: Double, peak: Double? = nil) -> Bucket {
    Bucket(start: 0, sum: average, count: 1, peak: peak ?? average)
}

/// One reading a minute for `minutes` minutes, plus one more so the last window closes.
@MainActor
private func fill(_ archive: HistoryArchive, from start: Date, minutes: Int, _ values: [Metric: Double]) {
    for i in 0...minutes { archive.record(values, at: start.addingTimeInterval(TimeInterval(i * 60))) }
}

private let quiet: [Metric: Double] = [.cpu: 0.1, .gpu: 0.05, .memory: 0.4]
private let hot: [Metric: Double] = [.cpu: 0.5, .gpu: 0.1, .memory: 0.4, .load: 100, .swapOut: 0, .pressure: 0, .thermal: 0]
private let calm: [Metric: Double] = [.cpu: 0.1, .gpu: 0.05, .memory: 0.4, .load: 1, .swapOut: 0, .pressure: 0, .thermal: 0]
private let now = date(2026, 11, 5)

@MainActor
private func report(_ archive: HistoryArchive, spikes: [Spike] = [], enabled: Bool = true, days: Int = 30,
                    now: Date = now) -> String {
    Report.text(archive: archive, spikes: spikes, spikesEnabled: enabled, now: now, days: days, cores: 10, calendar: ny)
}

@MainActor
private func classify(cpu: Double = 0.5, gpu: Double? = nil, load: Double? = nil, swap: Double? = nil,
                      pressure: Double? = nil, pressurePeak: Double? = nil, thermalPeak: Double? = nil) -> (state: Report.State, reasons: [Report.Reason]) {
    Report.classify(cpu: b(cpu), gpu: gpu.map { b($0) }, memory: nil, load: load.map { b($0) },
                    swapOut: swap.map { b($0) }, pressure: pressure.map { b($0, peak: pressurePeak) },
                    thermal: thermalPeak.map { b(0, peak: $0) }, cores: 10)
}

@MainActor
struct ClassifyTests {
    @Test func stateBoundaries() {
        #expect(classify(cpu: 0.9).state == .maxed)
        #expect(classify(cpu: 0.89).state == .busy)
        #expect(classify(cpu: 0.25).state == .busy)
        #expect(classify(cpu: 0.24, gpu: 0.24).state == .idle)
        #expect(classify(cpu: 0.24, gpu: 0.25).state == .busy)
        #expect(classify(cpu: 0.1, gpu: 0.9).state == .maxed)
        #expect(Report.classify(cpu: b(0.1), gpu: nil, memory: b(0.9), load: nil, swapOut: nil, pressure: nil,
                                thermal: nil, cores: 10).state == .maxed)
    }

    @Test func reasonBoundaries() {
        #expect(classify(load: 20).reasons == [.load])
        #expect(classify(load: 19.9).state == .busy)
        #expect(classify(pressure: 0.25).reasons == [.pressure])
        #expect(classify(pressure: 0.24).state == .busy)
        #expect(classify(pressure: 0.1, pressurePeak: 2).reasons == [.pressure])
        #expect(classify(pressure: 0.1, pressurePeak: 1).state == .busy)
        #expect(classify(swap: 5_000_000).reasons == [.swap])
        #expect(classify(swap: 4_999_999).state == .busy)
        #expect(classify(thermalPeak: 2).reasons == [.heat])
        #expect(classify(thermalPeak: 1).state == .busy)
    }

    @Test func missingSignalsNeverOverload() {
        let r = classify(cpu: 0.1)
        #expect(r.state == .idle)
        #expect(r.reasons.isEmpty)
        #expect(classify(cpu: 0.1, gpu: nil).state == .idle)
    }

    @Test func allReasonsInOrder() {
        let r = classify(load: 50, swap: 9_000_000, pressure: 0.5, thermalPeak: 3)
        #expect(r.state == .overloaded)
        #expect(r.reasons == [.load, .pressure, .swap, .heat])
    }

    @Test func durations() {
        #expect(Report.duration(0) == "under 1m")
        #expect(Report.duration(59) == "under 1m")
        #expect(Report.duration(60) == "1m")
        #expect(Report.duration(45 * 60) == "45m")
        #expect(Report.duration(2 * 3600) == "2h")
        #expect(Report.duration(2 * 3600 + 45 * 60) == "2h 45m")
        #expect(Report.duration(3 * 86_400) == "3d")
        #expect(Report.duration(3 * 86_400 + 4 * 3600) == "3d 4h")
    }
}

@MainActor
struct ReportTextTests {
    @Test func emptyArchive() {
        #expect(report(HistoryArchive(file: nil)) == "No history yet. Chrono records while the menu bar app is running.")
    }

    @Test func verdicts() {
        // 10 hours calm, then some hot time, all measured.
        func verdict(hotMinutes: Int, calmMinutes: Int, busy: Bool = false) -> String {
            let a = HistoryArchive(file: nil)
            let start = date(2026, 11, 4, 0, 0)
            fill(a, from: start, minutes: calmMinutes, busy ? calm.merging([.cpu: 0.5]) { $1 } : calm)
            fill(a, from: start.addingTimeInterval(TimeInterval((calmMinutes + 1) * 60)), minutes: hotMinutes, hot)
            return report(a).components(separatedBy: "\n\n")[1]
        }
        #expect(verdict(hotMinutes: 120, calmMinutes: 480).hasPrefix("Pushed too far: overloaded"))
        #expect(verdict(hotMinutes: 14, calmMinutes: 480).hasPrefix("Busy, with some overload: overloaded"))
        #expect(verdict(hotMinutes: 0, calmMinutes: 480) == "Plenty of headroom: idle 100% of the time.")
        #expect(verdict(hotMinutes: 0, calmMinutes: 480, busy: true) == "Well used: busy or maxed 100% of the time. Rarely overloaded.")
        #expect(verdict(hotMinutes: 120, calmMinutes: 480).contains("%"))
    }

    @Test func mixedRangeAndSignalsNote() {
        let a = HistoryArchive(file: nil)
        fill(a, from: date(2026, 11, 3, 10), minutes: 120, quiet)
        fill(a, from: date(2026, 11, 4, 10), minutes: 120, hot)
        let text = report(a)
        #expect(text.contains("of the measured time"))
        #expect(text.contains("Overload signals started Nov 4, so earlier time can only show as Idle, Busy or Maxed."))
        #expect(text.contains("Overloaded"))
        #expect(text.contains("(work waiting"))
        #expect(!text.hasSuffix("\n"))
    }

    @Test func noMeasuredWindows() {
        let a = HistoryArchive(file: nil)
        fill(a, from: date(2026, 11, 4, 10), minutes: 120, [.cpu: 0.5, .gpu: 0.1, .memory: 0.4])
        let text = report(a)
        #expect(text.contains("Overload signals haven't been recorded yet, so this time can only show as Idle, Busy or Maxed."))
        #expect(text.contains("Well used: busy or maxed 100% of the time."))
        #expect(!text.contains("Rarely overloaded."))
        #expect(!text.contains("Load "))
    }

    @Test func allMeasuredHasNoNote() {
        let a = HistoryArchive(file: nil)
        fill(a, from: date(2026, 11, 4, 10), minutes: 120, calm)
        let text = report(a)
        #expect(!text.contains("Overload signals"))
        #expect(!text.contains("measured time"))
        #expect(text.contains("Load "))
        #expect(text.contains("(10 cores)"))
        #expect(text.contains("Highest memory pressure: Normal. Highest thermal state: Nominal."))
    }

    @Test func rangeExcludesOlderWindows() {
        let a = HistoryArchive(file: nil)
        fill(a, from: date(2026, 10, 20, 10), minutes: 120, quiet)
        fill(a, from: date(2026, 11, 4, 10), minutes: 120, quiet)
        let seven = report(a, days: 7)
        #expect(seven.hasPrefix("Chrono report: last 7 days\nRecorded Nov 4 to Nov 4"))
        #expect(!seven.contains("Oct"))
        let one = report(a, days: 1, now: date(2026, 11, 5, 11))
        #expect(one.hasPrefix("Chrono report: last 1 day\n"))
        #expect(report(a, days: 30).contains("Recorded Oct 20 to Nov 4"))
        // Spikes outside the range are left out as well.
        let old = Spike(metric: .cpu, start: Int(date(2026, 10, 1).timeIntervalSince1970),
                        end: Int(date(2026, 10, 1, 1).timeIntervalSince1970), peak: 1, processes: [])
        #expect(report(a, spikes: [old], days: 7).contains("Spikes: none"))
    }

    @Test func byDayGroupsByLocalMidnight() {
        let a = HistoryArchive(file: nil)
        fill(a, from: date(2026, 11, 3, 23, 45), minutes: 29, quiet)
        let lines = report(a).components(separatedBy: "\n").filter { $0.hasPrefix("  Nov") }
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("  Nov 3"))
        #expect(lines[1].hasPrefix("  Nov 4"))
    }

    @Test func byDayAcrossDaylightSavingChange() {
        let a = HistoryArchive(file: nil)
        fill(a, from: date(2026, 10, 31, 20), minutes: 60 * 30, quiet)  // spans the 25-hour day, Nov 1
        let text = report(a, now: date(2026, 11, 3))
        let rows = text.components(separatedBy: "\n").filter { $0.hasPrefix("  Oct") || $0.hasPrefix("  Nov") }
        #expect(rows.count == 3)
        #expect(rows[1].hasPrefix("  Nov 1"))
    }

    @Test func byDayKeepsFourteen() {
        let a = HistoryArchive(file: nil)
        for d in 0..<20 { fill(a, from: date(2026, 10, 16 + d, 12), minutes: 30, quiet) }
        let text = report(a, now: date(2026, 11, 6))
        #expect(text.contains("By day (last 14)"))
        #expect(text.components(separatedBy: "\n").filter { $0.contains("   CPU ") }.count == 14)
        let few = HistoryArchive(file: nil)
        for d in 0..<14 { fill(few, from: date(2026, 10, 22 + d, 12), minutes: 30, quiet) }
        #expect(report(few, now: date(2026, 11, 6)).contains("By day\n"))
    }

    // MARK: spikes

    private func spike(_ metric: SpikeMetric, _ start: Date, _ end: Date, _ procs: [SpikeProcess] = []) -> Spike {
        Spike(metric: metric, start: Int(start.timeIntervalSince1970), end: Int(end.timeIntervalSince1970), peak: 0.98, processes: procs)
    }

    private func base() -> HistoryArchive {
        let a = HistoryArchive(file: nil)
        fill(a, from: date(2026, 11, 4, 10), minutes: 60, quiet)
        return a
    }

    @Test func spikeRows() {
        let procs = [SpikeProcess(name: "swift-frontend", cpu: 12.64, memory: 3 << 30),
                     SpikeProcess(name: "Simulators", cpu: 14.2, memory: 1 << 30),
                     SpikeProcess(name: "Xcode", cpu: 1.04, memory: 8 << 30),
                     SpikeProcess(name: "Safari", cpu: 1.0, memory: 100 << 20),
                     SpikeProcess(name: "zeroed", cpu: 0, memory: 0)]
        let same = spike(.cpu, date(2026, 11, 4, 13, 15), date(2026, 11, 4, 16, 45), procs)
        let across = spike(.memory, date(2026, 11, 2, 23, 50), date(2026, 11, 3, 1, 10), procs)
        let text = report(base(), spikes: [across, same])
        #expect(text.contains("Spikes (2)"))
        #expect(text.contains("Nov 4 13:15–16:45"))
        #expect(text.contains("Nov 2 23:50–Nov 3 01:10"))
        #expect(text.contains("Simulators 14.2 cores, swift-frontend 12.6 cores, Xcode 1.0 core"))
        #expect(text.contains("Xcode 8.0 GB, swift-frontend 3.0 GB, Simulators 1.0 GB"))
        #expect(!text.contains("zeroed"))
        #expect(text.contains("Only your own processes can be named."))
        #expect(!text.contains("Per-process GPU"))
        #expect(text.range(of: "Nov 4 13:15")!.lowerBound < text.range(of: "Nov 2 23:50")!.lowerBound)
    }

    @Test func emptyProcessesAndGPULine() {
        let gpu = spike(.gpu, date(2026, 11, 4, 11), date(2026, 11, 4, 11, 30),
                        [SpikeProcess(name: "ollama", cpu: 2, memory: 0)])
        let text = report(base(), spikes: [gpu])
        #expect(text.contains("no processes captured"))
        #expect(text.contains("Per-process GPU use isn't available, so GPU spikes list the largest processes by memory."))
    }

    @Test func spikesCapAtFifteen() {
        let many = (0..<20).map { i in
            spike(.cpu, date(2026, 11, 4, 10, i), date(2026, 11, 4, 10, i, ).addingTimeInterval(120))
        }
        let text = report(base(), spikes: many)
        #expect(text.contains("Spikes (15 most recent of 20)"))
        #expect(text.components(separatedBy: "\n").filter { $0.hasPrefix("  Nov 4 10:") }.count == 15)
    }

    @Test func spikesSwitch() {
        let one = spike(.cpu, date(2026, 11, 4, 11), date(2026, 11, 4, 11, 30))
        let off = report(base(), spikes: [one], enabled: false)
        #expect(off.hasSuffix("Spikes: process names are off in Settings"))
        #expect(!off.contains("Nov 4 11:00"))
        #expect(report(base(), spikes: [], enabled: false).hasSuffix("Spikes: process names are off in Settings"))
        #expect(report(base(), spikes: [], enabled: true).hasSuffix("Spikes: none recorded"))
    }

    @Test func zeroTimeShowsADash() {
        let lines = report(base()).components(separatedBy: "\n")
        #expect(lines.contains { $0.hasPrefix("  Overloaded") && $0.hasSuffix("0%   -") })
        #expect(lines.contains { $0.hasPrefix("  Maxed") && $0.hasSuffix("0%   -") })
    }
}
