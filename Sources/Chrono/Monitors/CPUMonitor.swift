import Foundation

struct CoreCluster: Identifiable {
    let name: String
    let cores: Range<Int>
    var id: String { name }
}

struct CPUSample {
    var user: Double = 0
    var system: Double = 0
    var cores: [Double] = []
    var load: (Double, Double, Double) = (0, 0, 0)

    var total: Double { min(1, user + system) }
}

final class CPUMonitor {
    let clusters: [CoreCluster]
    private var previous: [[UInt32]] = []

    init() {
        // Logical CPUs are numbered from the lowest perf level up (e.g. on M5 Max:
        // cpu0-11 "Performance", cpu12-17 "Super"), so walk perf levels in reverse.
        let levels = Sysctl.int("hw.nperflevels") ?? 1
        var result: [CoreCluster] = []
        var start = 0
        for level in stride(from: levels - 1, through: 0, by: -1) {
            let count = Sysctl.int("hw.perflevel\(level).logicalcpu") ?? 0
            let name = Sysctl.string("hw.perflevel\(level).name") ?? "Cores"
            guard count > 0 else { continue }
            result.append(CoreCluster(name: name, cores: start..<(start + count)))
            start += count
        }
        if result.isEmpty {
            result = [CoreCluster(name: "Cores", cores: 0..<ProcessInfo.processInfo.activeProcessorCount)]
        }
        clusters = result
        _ = sample()
    }

    func sample() -> CPUSample {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info
        else { return CPUSample() }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        var current: [[UInt32]] = []
        for cpu in 0..<Int(cpuCount) {
            current.append((0..<states).map { UInt32(bitPattern: info[cpu * states + $0]) })
        }
        defer { previous = current }
        guard previous.count == current.count else { return CPUSample() }

        var sample = CPUSample()
        var totalUser = 0.0, totalSystem = 0.0, totalAll = 0.0
        for (now, before) in zip(current, previous) {
            let user = Double(now[Int(CPU_STATE_USER)] &- before[Int(CPU_STATE_USER)])
                + Double(now[Int(CPU_STATE_NICE)] &- before[Int(CPU_STATE_NICE)])
            let system = Double(now[Int(CPU_STATE_SYSTEM)] &- before[Int(CPU_STATE_SYSTEM)])
            let idle = Double(now[Int(CPU_STATE_IDLE)] &- before[Int(CPU_STATE_IDLE)])
            let all = user + system + idle
            sample.cores.append(all > 0 ? (user + system) / all : 0)
            totalUser += user
            totalSystem += system
            totalAll += all
        }
        if totalAll > 0 {
            sample.user = totalUser / totalAll
            sample.system = totalSystem / totalAll
        }

        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        sample.load = (loads[0], loads[1], loads[2])
        return sample
    }
}
