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

struct SimulatorProcessTests {
    @Test func recognizesSimulatorRuntimePaths() {
        #expect(ProcessMonitor.isSimulatorPath(
            "/private/var/run/com.apple.security.cryptexd/mnt/com.apple.iPhoneOS.SimulatorRuntime-v24.1/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 27.0.simruntime/Contents/Resources/RuntimeRoot/Applications/PosterBoard.app/PosterBoard"))
        #expect(ProcessMonitor.isSimulatorPath(
            "/Library/Developer/CoreSimulator/Volumes/iOS_23A343/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 26.0.simruntime/Contents/Resources/RuntimeRoot/usr/libexec/diagnosticd"))
    }

    @Test func leavesMacProcessesAlone() {
        #expect(!ProcessMonitor.isSimulatorPath("/usr/libexec/diagnosticd"))
        #expect(!ProcessMonitor.isSimulatorPath("/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator"))
        #expect(!ProcessMonitor.isSimulatorPath(
            "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/XPCServices/com.apple.CoreSimulator.CoreSimulatorService.xpc/Contents/MacOS/com.apple.CoreSimulator.CoreSimulatorService"))
    }
}

struct DiskVolumeTests {
    @Test func fallsBackToPlainAvailableCapacity() {
        #expect(DiskMonitor.available(important: 5, plain: 7) == 5)
        #expect(DiskMonitor.available(important: 0, plain: 7) == 7)
        #expect(DiskMonitor.available(important: nil, plain: nil) == 0)
    }

    @Test func ordersBootFirstThenByName() {
        let volumes = [
            VolumeInfo(name: "Studio Offload", path: "/Volumes/Studio Offload", total: 100, available: 50),
            VolumeInfo(name: "Macintosh HD", path: "/", total: 100, available: 50),
            VolumeInfo(name: "Ginger", path: "/Volumes/Ginger", total: 100, available: 50),
        ]
        let ordered = DiskMonitor.ordered(volumes)
        #expect(ordered.map(\.path) == ["/", "/Volumes/Ginger", "/Volumes/Studio Offload"])
    }
}
