import Foundation
import IOKit

struct GPUSample {
    var utilization: Double = 0       // 0...1
    var renderer: Double = 0          // 0...1
    var memoryInUse: UInt64 = 0
}

final class GPUMonitor {
    let name: String
    let coreCount: Int?

    init() {
        var name = "GPU"
        var cores: Int?
        Self.forEachAccelerator { props in
            if let model = props["model"] as? String { name = model }
            if let count = props["gpu-core-count"] as? Int { cores = count }
        }
        self.name = name
        self.coreCount = cores
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
