import Foundation
import IOKit

struct VolumeInfo: Identifiable {
    let name: String
    let path: String
    let total: Int64
    let available: Int64
    var id: String { path }
    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct DiskSample {
    var readRate: Double = 0   // bytes/sec
    var writeRate: Double = 0  // bytes/sec
    var volumes: [VolumeInfo] = []

    var boot: VolumeInfo? { volumes.first { $0.path == "/" } ?? volumes.first }
}

final class DiskMonitor {
    private var previous: (read: UInt64, write: UInt64, time: Double)?
    private var cachedVolumes: [VolumeInfo] = []
    private var volumesFetchedAt: Double = -.infinity

    /// `volumes` enables the (comparatively slow) capacity lookup.
    func sample(volumes includeVolumes: Bool) -> DiskSample {
        let (read, write) = Self.ioCounters()
        let now = ProcessInfo.processInfo.systemUptime
        var sample = DiskSample()
        if let previous, now > previous.time {
            let dt = now - previous.time
            sample.readRate = read >= previous.read ? Double(read - previous.read) / dt : 0
            sample.writeRate = write >= previous.write ? Double(write - previous.write) / dt : 0
        }
        previous = (read, write, now)

        // Capacity changes slowly and "available for important usage" goes through CacheDelete
        // (~30ms), so refresh it every 30s.
        if includeVolumes, now - volumesFetchedAt > 30 {
            cachedVolumes = Self.volumes()
            volumesFetchedAt = now
        }
        sample.volumes = cachedVolumes
        return sample
    }

    private static func ioCounters() -> (UInt64, UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS
        else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0, write: UInt64 = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return (read, write)
    }

    static func available(important: Int64?, plain: Int?) -> Int64 {
        if let important, important > 0 { return important }
        if let plain, plain > 0 { return Int64(plain) }
        return 0
    }

    static func ordered(_ volumes: [VolumeInfo]) -> [VolumeInfo] {
        volumes.sorted { a, b in
            if (a.path == "/") != (b.path == "/") { return a.path == "/" }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private static func volumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return ordered(urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable != false,
                  let total = values.volumeTotalCapacity, total > 0 else { return nil }
            let available = available(important: values.volumeAvailableCapacityForImportantUsage,
                                      plain: values.volumeAvailableCapacity)
            return VolumeInfo(name: values.volumeName ?? url.lastPathComponent, path: url.path,
                              total: Int64(total), available: available)
        })
    }
}
