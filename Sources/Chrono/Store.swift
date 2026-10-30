import Foundation
import Observation

struct History {
    static let capacity = 90
    private(set) var values: [Double] = []

    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > Self.capacity { values.removeFirst(values.count - Self.capacity) }
    }

    var last: Double { values.last ?? 0 }
    var peak: Double { values.max() ?? 0 }
}

/// Owns every monitor and runs them off the main thread.
private final class Sampler: @unchecked Sendable {
    let cpu = CPUMonitor()
    let memory = MemoryMonitor()
    let network = NetworkMonitor()
    let disk = DiskMonitor()
    let gpu = GPUMonitor()
    let sensors = SensorMonitor()
    let battery = BatteryMonitor()
    let processes = ProcessMonitor()

    struct Snapshot: @unchecked Sendable {
        var cpu: CPUSample
        var memory: MemorySample
        var network: NetworkSample
        var disk: DiskSample
        var gpu: GPUSample
        var sensors: SensorSample?
        var battery: BatterySample?
        var processes: [ProcessUsage]?
    }

    func sample(active: Set<Module>, processes includeProcesses: Bool) -> Snapshot {
        Snapshot(
            cpu: cpu.sample(),
            memory: memory.sample(),
            network: network.sample(),
            disk: disk.sample(volumes: active.contains(.disk)),
            gpu: gpu.sample(),
            sensors: active.contains(.sensors) || active.contains(.gpu) ? sensors.sample() : nil,
            battery: battery.sample(),
            processes: includeProcesses ? processes.sample() : nil
        )
    }
}

@MainActor
@Observable
final class Store {
    private(set) var cpu = CPUSample()
    private(set) var memory = MemorySample()
    private(set) var network = NetworkSample()
    private(set) var disk = DiskSample()
    private(set) var gpu = GPUSample()
    private(set) var sensors = SensorSample()
    private(set) var battery: BatterySample?
    private(set) var processes: [ProcessUsage] = []

    private(set) var cpuHistory = History()
    private(set) var memoryHistory = History()
    private(set) var gpuHistory = History()
    private(set) var uploadHistory = History()
    private(set) var downloadHistory = History()
    private(set) var readHistory = History()
    private(set) var writeHistory = History()
    private(set) var temperatureHistory = History()
    private(set) var powerHistory = History()

    /// Long-term history behind the 1H–30D chart ranges.
    @ObservationIgnored let archive: HistoryArchive
    /// Chart range, shared by every panel so switching panels keeps the same time window.
    var chartRange: HistoryRange = .live

    @ObservationIgnored let clusters: [CoreCluster]
    @ObservationIgnored let gpuName: String
    @ObservationIgnored let gpuCores: Int?
    @ObservationIgnored let hasFans: Bool

    /// Number of open panels that show the process list; processes are only sampled while > 0.
    @ObservationIgnored var processConsumers = 0
    /// Modules shown in the menu bar or open as a panel. Slower readings (sensors, volume
    /// capacity) are skipped for modules nobody is looking at.
    @ObservationIgnored var activeModules: Set<Module> = Set(Module.allCases)
    /// Called on the main thread after every sample.
    @ObservationIgnored var onUpdate: (() -> Void)?

    @ObservationIgnored private let sampler = Sampler()
    @ObservationIgnored private let queue = DispatchQueue(label: "chrono.sampler", qos: .utility)
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var ticks = 0

    init(archive: HistoryArchive? = nil) {
        self.archive = archive ?? HistoryArchive()
        clusters = sampler.cpu.clusters
        gpuName = sampler.gpu.name
        gpuCores = sampler.gpu.coreCount
        hasFans = sampler.sensors.hasFans
    }

    func start(interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        let wantsProcesses = processConsumers > 0
        // Sensors are skipped while nobody shows them, but read them every 30 seconds or so
        // regardless so temperature and power history has no holes.
        ticks += 1
        let active = ticks % 15 == 1 ? activeModules.union([.sensors]) : activeModules
        let sampler = sampler
        queue.async {
            let snapshot = sampler.sample(active: active, processes: wantsProcesses)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.apply(snapshot)
                    self.inFlight = false
                }
            }
        }
    }

    /// Synchronous sample, used by the snapshot/dump modes.
    func refreshNow(processes: Bool = true) {
        apply(sampler.sample(active: Set(Module.allCases), processes: processes))
    }

    private func apply(_ s: Sampler.Snapshot) {
        cpu = s.cpu
        memory = s.memory
        network = s.network
        disk = s.disk
        gpu = s.gpu
        battery = s.battery
        if let sensors = s.sensors { self.sensors = sensors }
        if let processes = s.processes { self.processes = processes }

        cpuHistory.append(cpu.total)
        memoryHistory.append(memory.usedFraction)
        gpuHistory.append(gpu.utilization)
        uploadHistory.append(network.upRate)
        downloadHistory.append(network.downRate)
        readHistory.append(disk.readRate)
        writeHistory.append(disk.writeRate)
        if let t = sensors.cpu { temperatureHistory.append(t) }
        if let p = sensors.systemPower { powerHistory.append(p) }

        var values: [Metric: Double] = [
            .cpu: cpu.total, .memory: memory.usedFraction, .gpu: gpu.utilization,
            .upload: network.upRate, .download: network.downRate, .read: disk.readRate, .write: disk.writeRate,
        ]
        if let fresh = s.sensors {
            values[.temperature] = fresh.cpu
            values[.power] = fresh.systemPower
        }
        archive.record(values)
        onUpdate?()
    }

    func liveHistory(_ metric: Metric) -> History {
        switch metric {
        case .cpu: cpuHistory
        case .memory: memoryHistory
        case .gpu: gpuHistory
        case .upload: uploadHistory
        case .download: downloadHistory
        case .read: readHistory
        case .write: writeHistory
        case .temperature: temperatureHistory
        case .power: powerHistory
        }
    }

    func topProcesses(by key: KeyPath<ProcessUsage, some Comparable>, limit: Int = 5) -> [ProcessUsage] {
        Array(processes.sorted { $0[keyPath: key] > $1[keyPath: key] }.prefix(limit))
    }
}
