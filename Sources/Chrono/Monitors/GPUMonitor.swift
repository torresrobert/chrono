import CSensors
import Foundation
import IOKit

struct GPUSample {
    var utilization: Double = 0       // 0...1
    var renderer: Double = 0          // 0...1
    var memoryInUse: UInt64 = 0
    /// Average clock while the GPU was busy, in MHz; nil if it never was, or where IOReport is unavailable.
    var clock: Double?
    /// GPU power in watts, from the chip's energy counters.
    var power: Double?
}

final class GPUMonitor {
    let name: String
    let coreCount: Int?
    /// Highest GPU clock in MHz, when the clock is readable.
    let maxClock: Double?
    private let readsPerformance: Bool

    init() {
        var name = "GPU"
        var cores: Int?
        Self.forEachAccelerator { props in
            if let model = props["model"] as? String { name = model }
            if let count = props["gpu-core-count"] as? Int { cores = count }
        }
        self.name = name
        self.coreCount = cores
        readsPerformance = gpu_perf_open() == 0
        let max = gpu_perf_max_megahertz()
        maxClock = readsPerformance && max > 0 ? max : nil
    }

    func sample() -> GPUSample {
        var sample = GPUSample()
        Self.forEachAccelerator(property: "PerformanceStatistics") { props in
            guard let stats = props["PerformanceStatistics"] as? [String: Any] else { return }
            if let device = stats["Device Utilization %"] as? Int {
                sample.utilization = max(sample.utilization, Double(device) / 100)
            }
            if let renderer = stats["Renderer Utilization %"] as? Int {
                sample.renderer = max(sample.renderer, Double(renderer) / 100)
            }
            if let memory = stats["In use system memory"] as? Int {
                sample.memoryInUse += UInt64(memory)
            }
        }
        // Utilization says how much of the time the GPU was busy, not how hard it worked: a
        // local model keeps it busy nonstop. The clock and power show the difference.
        var perf = gpu_perf_t()
        if readsPerformance, gpu_perf_sample(&perf) == 0 {
            if perf.active > 0, perf.megahertz > 0 { sample.clock = perf.megahertz }
            if perf.watts >= 0 { sample.power = perf.watts }
        }
        return sample
    }

    /// Calls `body` with each accelerator's registry properties. Pass `property` to fetch just
    /// that one key, which is much cheaper than copying the whole (large) property table.
    private static func forEachAccelerator(property: String? = nil, _ body: ([String: Any]) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let property {
                if let value = IORegistryEntryCreateCFProperty(service, property as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() {
                    body([property: value])
                }
                continue
            }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else { continue }
            body(dict)
        }
    }
}
