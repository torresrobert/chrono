import Foundation

// Spike log: when CPU, memory or GPU averages 90% or more over 30 seconds, the busiest processes
// are sampled (at the start and every 5 minutes) so the cause can be seen later. Only names and
// totals are kept, never paths, arguments, pids or window titles. Stored next to the history file.

enum SpikeMetric: String, CaseIterable, Codable { case cpu, memory, gpu }

struct SpikeProcess: Codable, Equatable {
    var name: String
    var cpu: Double      // highest seen, in cores (1.0 == one full core), summed across same-named processes
    var memory: UInt64   // highest seen, bytes, summed across same-named processes
}

struct Spike: Codable, Equatable {
    var metric: SpikeMetric
    var start: Int       // seconds since 1970: time of the oldest reading in the window that opened it
    var end: Int         // last time the metric was hot
    var peak: Double     // highest single reading while open, including the opening window, 0...1
    var processes: [SpikeProcess]
}

struct SpikeDetector: Equatable {
    static let threshold = 0.9
    static let sustain = 30
    static let closeAfter = 120
    static let captureEvery = 300
    static let maxGap = 60
    static let keep = 5

    private struct Reading: Equatable {
        var time: Int
        var value: Double
    }

    private var windows: [SpikeMetric: [Reading]] = [:]
    private var open: [SpikeMetric: Spike] = [:]
    private var lastTime: Int?
    private var captureDue = false
    private var primed = false
    private var nextCapture = 0

    var openSpikes: [Spike] {
        open.values.sorted { ($0.start, $0.metric.rawValue) < ($1.start, $1.metric.rawValue) }
    }
    var wantsProcesses: Bool { !open.isEmpty && captureDue }

    /// Returns the spikes this call closed.
    mutating func observe(_ readings: [SpikeMetric: Double], at time: Int) -> [Spike] {
        var closed: [Spike] = []
        if let last = lastTime, time - last > Self.maxGap || time < last {
            // Asleep, stalled or the clock moved: the gap can't be vouched for either way.
            closed += openSpikes
            open.removeAll()
            windows.removeAll()
        }
        lastTime = time

        for metric in SpikeMetric.allCases {
            guard let value = readings[metric], value.isFinite else { continue }
            var window = windows[metric] ?? []
            window.append(Reading(time: time, value: value))
            // Keep one reading at or before the cutoff so the window always spans `sustain`, even with jitter.
            while window.count >= 2, window[1].time <= time - Self.sustain { window.removeFirst() }
            windows[metric] = window

            let mean = window.reduce(0.0) { $0 + $1.value } / Double(window.count)
            let hot = window[0].time <= time - Self.sustain && mean >= Self.threshold

            if var spike = open[metric] {
                spike.peak = max(spike.peak, value)
                if hot {
                    spike.end = time
                } else if time - spike.end >= Self.closeAfter {
                    open[metric] = nil
                    closed.append(spike)
                    continue
                }
                open[metric] = spike
            } else if hot {
                open[metric] = Spike(metric: metric, start: window[0].time, end: time,
                                     peak: window.map(\.value).max() ?? value, processes: [])
                captureDue = true
            }
        }

        if open.isEmpty {
            captureDue = false
            primed = false
        } else if !captureDue, time >= nextCapture {
            captureDue = true
        }
        return closed
    }

    /// CPU per process comes from the change between two samples, so the first list of a
    /// capture is only used to prime the monitor.
    mutating func receive(_ processes: [ProcessUsage], at time: Int) {
        guard !open.isEmpty else {
            captureDue = false
            primed = false
            return
        }
        guard captureDue else { return }
        guard primed else {
            primed = true
            return
        }
        let groups = Self.summarize(processes)
        for (metric, var spike) in open {
            spike.processes = Self.prune(Self.merge(spike.processes, groups))
            open[metric] = spike
        }
        primed = false
        captureDue = false
        nextCapture = time + Self.captureEvery
    }

    /// Sums by name (all simulator processes are one group), then keeps the top groups.
    static func summarize(_ processes: [ProcessUsage]) -> [SpikeProcess] {
        var groups: [String: SpikeProcess] = [:]
        for p in processes {
            let name = p.isSimulator ? "Simulators" : p.name
            var group = groups[name] ?? SpikeProcess(name: name, cpu: 0, memory: 0)
            group.cpu += p.cpu
            group.memory += p.memory
            groups[name] = group
        }
        return prune(Array(groups.values))
    }

    private static func merge(_ old: [SpikeProcess], _ new: [SpikeProcess]) -> [SpikeProcess] {
        var byName: [String: SpikeProcess] = [:]
        for p in old { byName[p.name] = p }
        for p in new {
            if var existing = byName[p.name] {
                existing.cpu = max(existing.cpu, p.cpu)
                existing.memory = max(existing.memory, p.memory)
                byName[p.name] = existing
            } else {
                byName[p.name] = p
            }
        }
        return Array(byName.values)
    }

    /// Union of the top 5 by cpu and the top 5 by memory, ties broken by name.
    private static func prune(_ groups: [SpikeProcess]) -> [SpikeProcess] {
        func byCPU(_ a: SpikeProcess, _ b: SpikeProcess) -> Bool {
            a.cpu != b.cpu ? a.cpu > b.cpu : a.name < b.name
        }
        let topCPU = groups.sorted(by: byCPU).prefix(keep)
        let topMemory = groups.sorted { $0.memory != $1.memory ? $0.memory > $1.memory : $0.name < $1.name }.prefix(keep)
        var seen = Set<String>()
        let union = (Array(topCPU) + Array(topMemory)).filter { seen.insert($0.name).inserted }
        return union.sorted(by: byCPU)
    }
}

@MainActor
final class SpikeLog {
    private var detector = SpikeDetector()
    private var closed: [Spike] = []
    private(set) var enabled = true

    private let file: URL?
    private let saves: Bool
    private var lastSave = Date()
    private let writer = DispatchQueue(label: "chrono.spikes", qos: .utility)

    nonisolated static let defaultFile = HistoryArchive.defaultFile
        .deletingLastPathComponent()
        .appendingPathComponent("spikes.plist")

    private static let retention: TimeInterval = 31 * 86_400
    private static let limit = 1000

    private struct Stored: Codable {
        var version = 1
        var spikes: [Spike]
    }

    init(file: URL? = SpikeLog.defaultFile, saves: Bool = false) {
        self.file = file
        self.saves = saves && file != nil
        if let file, let data = try? Data(contentsOf: file),
           let stored = try? PropertyListDecoder().decode(Stored.self, from: data), stored.version == 1 {
            closed = stored.spikes
            tidy(now: Date())
        }
    }

    var wantsProcesses: Bool { enabled && detector.wantsProcesses }

    /// Closed spikes plus the ones still open, oldest first.
    var all: [Spike] { (closed + detector.openSpikes).sorted { $0.start < $1.start } }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        guard !on else { return }
        detector = SpikeDetector()
        closed = []
        // Through the writer queue, so a save already queued can't bring the names back afterwards.
        if saves, let file { writer.sync { try? FileManager.default.removeItem(at: file) } }
    }

    func observe(_ readings: [SpikeMetric: Double], at date: Date = Date()) {
        guard enabled else { return }
        let ended = detector.observe(readings, at: Int(date.timeIntervalSince1970))
        if !ended.isEmpty {
            closed += ended
            tidy(now: date)
        }
        if saves, date.timeIntervalSince(lastSave) > 300 {
            tidy(now: date)  // also here, so old names still expire on a Mac that has gone quiet
            save()
        }
    }

    func receive(_ processes: [ProcessUsage], at date: Date = Date()) {
        guard enabled else { return }
        detector.receive(processes, at: Int(date.timeIntervalSince1970))
    }

    private func tidy(now: Date) {
        let cutoff = Int(now.timeIntervalSince1970 - Self.retention)
        closed.removeAll { $0.end < cutoff }
        if closed.count > Self.limit {
            closed.sort { $0.start < $1.start }
            closed.removeFirst(closed.count - Self.limit)
        }
    }

    func save(synchronously: Bool = false) {
        guard saves, enabled, let file else { return }
        lastSave = Date()
        let stored = Stored(spikes: all)
        let write: @Sendable () -> Void = {
            do {
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                let data = try encoder.encode(stored)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
            } catch {
                NSLog("Chrono: saving spikes failed: \(error)")
            }
        }
        if synchronously { write() } else { writer.async(execute: write) }
    }
}
