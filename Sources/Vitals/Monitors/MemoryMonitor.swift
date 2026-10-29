import Foundation

enum MemoryPressure: String {
    case normal = "Normal", warning = "Warning", critical = "Critical"
}

struct MemorySample {
    var total: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressure: MemoryPressure = .normal

    var used: UInt64 { app + wired + compressed }
    var free: UInt64 { total > used ? total - used : 0 }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

final class MemoryMonitor {
    private let total = UInt64(Sysctl.int("hw.memsize") ?? 0)
    private let pageSize = UInt64(vm_kernel_page_size)

    func sample() -> MemorySample {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var sample = MemorySample(total: total)
        guard result == KERN_SUCCESS else { return sample }

        let page = { (n: natural_t) in UInt64(n) * self.pageSize }
        let anonymous = page(stats.internal_page_count)
        let purgeable = page(stats.purgeable_count)
        sample.app = anonymous > purgeable ? anonymous - purgeable : 0
        sample.wired = page(stats.wire_count)
        sample.compressed = page(stats.compressor_page_count)
        sample.cached = page(stats.external_page_count) + purgeable

        if let swap = Sysctl.value("vm.swapusage", as: xsw_usage.self) {
            sample.swapUsed = swap.xsu_used
            sample.swapTotal = swap.xsu_total
        }
        switch Sysctl.int("kern.memorystatus_vm_pressure_level") ?? 1 {
        case 4: sample.pressure = .critical
        case 2: sample.pressure = .warning
        default: sample.pressure = .normal
        }
        return sample
    }
}
