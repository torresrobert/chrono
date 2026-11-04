import Foundation
import Testing
@testable import Chrono

private func proc(_ name: String, cpu: Double = 0, memory: UInt64 = 0, sim: Bool = false, pid: Int32 = 1) -> ProcessUsage {
    ProcessUsage(pid: pid, name: name, cpu: cpu, memory: memory, isSimulator: sim)
}

private func tempFile(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("chrono-\(name)-\(UUID()).plist")
}

/// Feeds `value` at each time; returns spikes closed along the way.
@discardableResult
private func feed(_ d: inout SpikeDetector, _ value: Double, times: [Int], metric: SpikeMetric = .cpu) -> [Spike] {
    var closed: [Spike] = []
    for t in times { closed += d.observe([metric: value], at: t) }
    return closed
}

private func every2(_ from: Int, _ to: Int) -> [Int] { Array(stride(from: from, through: to, by: 2)) }

struct SpikeDetectorTests {
    @Test func shortBurstNeverOpens() {
        var d = SpikeDetector()
        feed(&d, 1.0, times: every2(0, 20))
        feed(&d, 0.0, times: every2(22, 200))
        #expect(d.openSpikes.isEmpty)
        #expect(!d.wantsProcesses)
    }

    @Test func sustainedLoadOpens() {
        var d = SpikeDetector()
        feed(&d, 0.95, times: every2(1000, 1040))
        #expect(d.openSpikes.count == 1)
        #expect(d.openSpikes[0].start == 1000)
        #expect(d.wantsProcesses)
    }

    @Test func oneDipDoesNotReset() {
        var d = SpikeDetector()
        for t in every2(0, 40) { _ = d.observe([.cpu: t == 20 ? 0.8 : 0.97], at: t) }
        #expect(d.openSpikes.count == 1)
    }

    @Test func jitteredTimesStillOpen() {
        var d = SpikeDetector()
        feed(&d, 1.0, times: [0, 5, 10, 16, 21, 26, 31, 36])
        #expect(d.openSpikes.count == 1)
    }

    @Test func closesTwoMinutesAfterLastHot() {
        var d = SpikeDetector()
        feed(&d, 1.0, times: every2(0, 60))
        var closed: [Spike] = []
        var t = 62
        while closed.isEmpty && t < 1000 {
            closed += d.observe([.cpu: 0.1], at: t)
            t += 2
        }
        #expect(closed.count == 1)
        #expect(closed[0].start == 0)
        #expect(closed[0].peak == 1.0)
        #expect(closed[0].end >= 60 && closed[0].end < 100)
        #expect(t - 2 - closed[0].end >= 120)
        #expect(d.openSpikes.isEmpty)
    }

    @Test func shortCoolStretchKeepsTheSameSpike() {
        var d = SpikeDetector()
        feed(&d, 1.0, times: every2(0, 60))
        feed(&d, 0.1, times: every2(62, 110))
        #expect(d.openSpikes.count == 1)
        let before = d.openSpikes[0].end
        let closed = feed(&d, 1.0, times: every2(112, 200))
        #expect(closed.isEmpty)
        #expect(d.openSpikes.count == 1)
        #expect(d.openSpikes[0].start == 0)
        #expect(d.openSpikes[0].end > before)
    }

    @Test func gapClosesAtLastHotTime() {
        var d = SpikeDetector()
        feed(&d, 1.0, times: every2(0, 60))
        let closed = d.observe([.cpu: 1.0], at: 660)
        #expect(closed.count == 1)
        #expect(closed[0].end == 60)
        #expect(d.openSpikes.isEmpty)
        feed(&d, 1.0, times: every2(662, 680))
        #expect(d.openSpikes.isEmpty)
        feed(&d, 1.0, times: every2(682, 700))
        #expect(d.openSpikes.count == 1)
        #expect(d.openSpikes[0].start == 660)
    }

    @Test func clockGoingBackwardsCloses() {
        var d = SpikeDetector()
        feed(&d, 1.0, times: every2(1000, 1060))
        let closed = d.observe([.cpu: 1.0], at: 500)
        #expect(closed.count == 1)
        #expect(closed[0].end == 1060)
        #expect(d.openSpikes.isEmpty)
    }

    @Test func captureSequence() {
        var d = SpikeDetector()
        feed(&d, 1.0, times: every2(0, 40))
        #expect(d.wantsProcesses)
        d.receive([proc("a", cpu: 1, memory: 10)], at: 42)  // priming list is discarded
        #expect(d.openSpikes[0].processes.isEmpty)
        #expect(d.wantsProcesses)
        d.receive([proc("a", cpu: 3, memory: 10), proc("b", cpu: 1, memory: 50)], at: 44)
        #expect(d.openSpikes[0].processes.map(\.name) == ["a", "b"])
        #expect(!d.wantsProcesses)
        feed(&d, 1.0, times: every2(46, 342))
        #expect(!d.wantsProcesses)
        feed(&d, 1.0, times: [344])
        #expect(d.wantsProcesses)
        d.receive([], at: 344)
        d.receive([proc("a", cpu: 2, memory: 99), proc("b", cpu: 5, memory: 5)], at: 346)
        var byName: [String: SpikeProcess] = [:]
        for p in d.openSpikes[0].processes { byName[p.name] = p }
        #expect(byName["a"] == SpikeProcess(name: "a", cpu: 3, memory: 99))
        #expect(byName["b"] == SpikeProcess(name: "b", cpu: 5, memory: 50))
    }

    @Test func groupingSumsAndPrunes() {
        let list = [proc("swift-frontend", cpu: 1, memory: 100, pid: 1), proc("swift-frontend", cpu: 1, memory: 100, pid: 2),
                    proc("swift-frontend", cpu: 1, memory: 100, pid: 3),
                    proc("SimA", cpu: 0.5, memory: 10, sim: true), proc("SimB", cpu: 0.5, memory: 10, sim: true)]
        let groups = SpikeDetector.summarize(list)
        var byName: [String: SpikeProcess] = [:]
        for p in groups { byName[p.name] = p }
        #expect(byName["swift-frontend"] == SpikeProcess(name: "swift-frontend", cpu: 3, memory: 300))
        #expect(byName["Simulators"] == SpikeProcess(name: "Simulators", cpu: 1, memory: 20))
        #expect(groups.count == 2)

        var many = (0..<20).map { proc("p\($0)", cpu: Double($0), memory: 1) }
        many.append(proc("hog", cpu: 0, memory: 1_000_000))
        let pruned = SpikeDetector.summarize(many)
        #expect(pruned.count == 10)  // top 5 by cpu, plus the memory-only hog and four memory ties broken by name
        #expect(pruned.contains { $0.name == "hog" })
        #expect(pruned.contains { $0.name == "p19" })
    }

    @Test func receiveWithoutCaptureDueChangesNothing() {
        var d = SpikeDetector()
        d.receive([proc("a", cpu: 1)], at: 5)
        #expect(d == SpikeDetector())
        feed(&d, 1.0, times: every2(0, 40))
        d.receive([], at: 42)
        d.receive([proc("a", cpu: 1)], at: 44)
        let snapshot = d
        d.receive([proc("z", cpu: 9)], at: 46)
        #expect(d == snapshot)
    }

    // The real monitor: its first list has no CPU figures, so this proves the priming step is what makes them work.
    @Test func capturesRealProcessesWithCPUFromTheSecondList() throws {
        var d = SpikeDetector()
        feed(&d, 1.0, times: every2(0, 40))
        let monitor = ProcessMonitor()
        d.receive(monitor.sample(), at: 42)
        let burnUntil = Date().addingTimeInterval(0.3)
        var spins = 0
        while Date() < burnUntil { spins += 1 }
        #expect(spins > 0)
        d.receive(monitor.sample(), at: 44)
        let spike = try #require(d.openSpikes.first)
        #expect(spike.processes.contains { $0.cpu > 0.1 })
        #expect(spike.processes.contains { $0.memory > 0 })
        #expect(spike.processes.allSatisfy { !$0.name.contains("/") })
    }

    @Test func metricsAreIndependentAndShareCaptures() {
        var d = SpikeDetector()
        for t in every2(0, 60) { _ = d.observe([.cpu: 1.0, .gpu: t < 40 ? 1.0 : 0.0], at: t) }
        #expect(d.openSpikes.map(\.metric).contains(.cpu))
        #expect(d.openSpikes.map(\.metric).contains(.gpu))
        d.receive([], at: 62)
        d.receive([proc("a", cpu: 1, memory: 5)], at: 64)
        #expect(d.openSpikes.allSatisfy { $0.processes.map(\.name) == ["a"] })
        var closed: [Spike] = []
        for t in every2(66, 300) { closed += d.observe([.cpu: 1.0, .gpu: 0.0], at: t) }
        #expect(closed.map(\.metric) == [.gpu])
        #expect(d.openSpikes.map(\.metric) == [.cpu])
    }
}

@MainActor
struct SpikeLogTests {
    private func hotLog(_ file: URL?, saves: Bool, base: Date) -> SpikeLog {
        let log = SpikeLog(file: file, saves: saves)
        for i in every2(0, 40) { log.observe([.cpu: 1.0], at: base.addingTimeInterval(TimeInterval(i))) }
        return log
    }

    @Test func roundTripsIncludingOpenSpike() {
        let file = tempFile("spikes")
        defer { try? FileManager.default.removeItem(at: file) }
        let log = hotLog(file, saves: true, base: Date())
        #expect(log.all.count == 1)
        log.save(synchronously: true)
        let reloaded = SpikeLog(file: file)
        #expect(reloaded.all == log.all)
        #expect(!reloaded.wantsProcesses)
    }

    @Test func prunesOldAndCaps() throws {
        let file = tempFile("spikes")
        defer { try? FileManager.default.removeItem(at: file) }
        let now = Int(Date().timeIntervalSince1970)
        var list = [Spike(metric: .cpu, start: now - 40 * 86_400, end: now - 40 * 86_400 + 60, peak: 1, processes: [])]
        for i in 0..<1200 { list.append(Spike(metric: .memory, start: now - 1000 + i, end: now - 1000 + i, peak: 1, processes: [])) }
        struct Stored: Codable { var version = 1; var spikes: [Spike] }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(Stored(spikes: list)).write(to: file)
        let log = SpikeLog(file: file)
        #expect(log.all.count == 1000)
        #expect(log.all.first?.start == now - 1000 + 200)
    }

    @Test func disablingEmptiesDeletesAndIgnores() {
        let file = tempFile("spikes")
        defer { try? FileManager.default.removeItem(at: file) }
        let base = Date()
        let log = hotLog(file, saves: true, base: base)
        log.save(synchronously: true)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(log.wantsProcesses)
        log.setEnabled(false)
        #expect(log.all.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!log.wantsProcesses)
        for i in every2(100, 200) { log.observe([.cpu: 1.0], at: base.addingTimeInterval(TimeInterval(i))) }
        #expect(log.all.isEmpty)
        log.save(synchronously: true)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        log.setEnabled(true)
        for i in every2(300, 340) { log.observe([.cpu: 1.0], at: base.addingTimeInterval(TimeInterval(i))) }
        #expect(log.all.count == 1)
    }

    // The whole path through a real Store: an open spike makes refresh() sample processes on its
    // own, with no panel open, and the names reach the saved file.
    @Test func storeSamplesProcessesForAnOpenSpike() async throws {
        let file = tempFile("spikes")
        defer { try? FileManager.default.removeItem(at: file) }
        let log = hotLog(file, saves: true, base: Date().addingTimeInterval(-40))
        #expect(log.wantsProcesses)

        let store = Store(archive: HistoryArchive(file: nil), spikes: log)
        #expect(store.processConsumers == 0)
        for _ in 0..<100 where log.wantsProcesses {
            store.refresh()
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!log.wantsProcesses)
        let spike = try #require(log.all.first)
        #expect(!spike.processes.isEmpty)

        log.save(synchronously: true)
        let saved = SpikeLog(file: file).all
        #expect(saved.first?.processes == spike.processes)
    }

    @Test func nonSavingLogNeverWrites() {
        let file = tempFile("spikes")
        let log = hotLog(file, saves: false, base: Date())
        log.save(synchronously: true)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func corruptFileLoadsEmpty() throws {
        let file = tempFile("spikes")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not a plist".utf8).write(to: file)
        #expect(SpikeLog(file: file).all.isEmpty)
    }
}

struct NewMetricTests {
    @Test func swapOutRateArithmetic() {
        #expect(MemoryMonitor.swapOutRate(current: 300, previous: 100, seconds: 2, pageSize: 16_384) == 200 * 16_384 / 2)
        #expect(MemoryMonitor.swapOutRate(current: 50, previous: 100, seconds: 2, pageSize: 16_384) == 0)
        #expect(MemoryMonitor.swapOutRate(current: 300, previous: 100, seconds: 0, pageSize: 16_384) == 0)
    }

    @Test func levelMappings() {
        #expect([MemoryPressure.normal, .warning, .critical].map(\.level) == [0, 1, 2])
        #expect([ProcessInfo.ThermalState.nominal, .fair, .serious, .critical].map(Metric.thermalLevel) == [0, 1, 2, 3])
    }

    private struct Stored: Codable {
        var version = 1
        var metrics: [String: MetricHistory]
    }

    private func sameSeries(_ a: [Bucket], _ b: [Bucket]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy {
            $0.start == $1.start && $0.count == $1.count && abs($0.average - $1.average) < 1e-6
        }
    }

    // `saves: false`: the archive would otherwise queue its own write over the file under test.
    @MainActor private func writeHistory(_ keys: [String], to file: URL, now: Date) throws -> HistoryArchive {
        let source = HistoryArchive(file: nil)
        for i in 0..<120 { source.record([.cpu: 0.4], at: now.addingTimeInterval(TimeInterval(i * 60 - 7200))) }
        let cpu = try #require(source.metrics[.cpu])
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(Stored(metrics: Dictionary(uniqueKeysWithValues: keys.map { ($0, cpu) }))).write(to: file)
        return source
    }

    @Test @MainActor func oldFormatHistoryStillLoads() throws {
        let file = tempFile("old-history")
        defer { try? FileManager.default.removeItem(at: file) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let source = try writeHistory(["cpu"], to: file, now: now)
        let loaded = HistoryArchive(file: file)
        #expect(!loaded.series(.cpu, range: .day, now: now).isEmpty)
        #expect(sameSeries(loaded.series(.cpu, range: .day, now: now), source.series(.cpu, range: .day, now: now)))
        #expect(loaded.series(.load, range: .day, now: now).isEmpty)
    }

    @Test @MainActor func unknownMetricKeyIsDropped() throws {
        let file = tempFile("future-history")
        defer { try? FileManager.default.removeItem(at: file) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let source = try writeHistory(["cpu", "someFutureMetric"], to: file, now: now)
        let loaded = HistoryArchive(file: file)
        #expect(!loaded.series(.cpu, range: .day, now: now).isEmpty)
        #expect(sameSeries(loaded.series(.cpu, range: .day, now: now), source.series(.cpu, range: .day, now: now)))
    }
}
