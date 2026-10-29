import Testing
@testable import Chrono

struct HistoryTests {
    @Test func keepsOnlyTheMostRecentSamples() {
        var history = History()
        for i in 0..<(History.capacity + 25) { history.append(Double(i)) }
        #expect(history.values.count == History.capacity)
        #expect(history.values.first == 25)
        #expect(history.last == Double(History.capacity + 24))
        #expect(history.peak == history.last)
    }
}

struct SensorKeySelectionTests {
    @Test func keepsSmallGroupsWhole() {
        #expect(SensorMonitor.spread(["Tp00", "Tp04"], limit: 6) == ["Tp00", "Tp04"])
    }

    @Test func spreadsLargeGroupsEvenly() {
        let keys = (0..<84).map { "Tg\($0)" }
        let picked = SensorMonitor.spread(keys, limit: 6)
        #expect(picked.count == 6)
        #expect(picked.first == "Tg0")
        #expect(Set(picked).count == 6)
        #expect(picked.last.map { keys.firstIndex(of: $0)! > 60 } == true)
    }
}

/// Live readings from the machine running the tests: sanity bounds only.
struct LiveMonitorTests {
    @Test func cpuLoadIsAFraction() {
        let monitor = CPUMonitor()
        let sample = monitor.sample()
        #expect((0...1).contains(sample.total))
        #expect(sample.cores.allSatisfy { (0...1).contains($0) })
        #expect(monitor.clusters.map(\.cores.count).reduce(0, +) == sample.cores.count)
    }

    @Test func memoryAddsUp() {
        let sample = MemoryMonitor().sample()
        #expect(sample.total > 0)
        #expect(sample.used <= sample.total)
        #expect((0...1).contains(sample.usedFraction))
    }

    @Test func networkRatesAreNonNegative() {
        let monitor = NetworkMonitor()
        _ = monitor.sample()
        let sample = monitor.sample()
        #expect(sample.upRate >= 0 && sample.downRate >= 0)
    }

    @Test func sensorsAreOptionalButSane() {
        // CI runners are VMs without an SMC; on real hardware every reading must be plausible.
        let sample = SensorMonitor().sample()
        for group in sample.groups {
            #expect((1...130).contains(group.average), "\(group.name)")
            #expect(group.maximum >= group.average)
        }
        for fan in sample.fans { #expect(fan.rpm >= 0) }
    }
}
