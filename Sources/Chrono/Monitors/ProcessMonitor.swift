import AppKit
import Darwin

struct ProcessUsage: Identifiable {
    let pid: pid_t
    let name: String
    let cpu: Double        // fraction of one core (1.0 == 100%)
    let memory: UInt64     // physical footprint, bytes
    var isSimulator = false  // runs inside an iOS/watchOS/visionOS Simulator runtime
    var id: pid_t { pid }
}

/// Samples per-process CPU and memory. Only processes owned by the current user are readable
/// without root, which covers the apps people actually care about in a menu bar monitor.
final class ProcessMonitor {
    private var previous: [pid_t: (cpuTime: UInt64, at: Double)] = [:]
    private var identities: [pid_t: (name: String, isSimulator: Bool)] = [:]

    func sample() -> [ProcessUsage] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return [] }

        let now = ProcessInfo.processInfo.systemUptime
        var next: [pid_t: (UInt64, Double)] = [:]
        var result: [ProcessUsage] = []
        result.reserveCapacity(count)

        for pid in pids.prefix(count) where pid > 0 {
            var usage = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) == 0
                }
            }
            guard ok else { continue }
            let cpuTime = usage.ri_user_time + usage.ri_system_time
            next[pid] = (cpuTime, now)

            var cpu = 0.0
            if let before = previous[pid], now > before.at, cpuTime >= before.cpuTime {
                cpu = Double(cpuTime - before.cpuTime) * MachTime.nanosPerTick / 1e9 / (now - before.at)
            }
            let identity = identity(for: pid)
            result.append(ProcessUsage(pid: pid, name: identity.name, cpu: cpu, memory: usage.ri_phys_footprint,
                                       isSimulator: identity.isSimulator))
        }
        previous = next
        identities = identities.filter { next[$0.key] != nil }
        return result
    }

    private func identity(for pid: pid_t) -> (name: String, isSimulator: Bool) {
        if let cached = identities[pid] { return cached }
        let name: String
        if let app = NSRunningApplication(processIdentifier: pid), let localized = app.localizedName {
            name = localized
        } else {
            var buf = [CChar](repeating: 0, count: 256)
            name = proc_name(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : "pid \(pid)"
        }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let isSimulator = proc_pidpath(pid, &path, UInt32(path.count)) > 0
            && Self.isSimulatorPath(String(cString: path))
        identities[pid] = (name, isSimulator)
        return (name, isSimulator)
    }

    /// Simulator processes execute from a runtime root (`….simruntime/Contents/Resources/RuntimeRoot/…`),
    /// mounted from a cryptex or installed under CoreSimulator, which no macOS process does.
    static func isSimulatorPath(_ path: String) -> Bool {
        path.contains("/CoreSimulator/") || path.contains(".simruntime/")
    }
}
