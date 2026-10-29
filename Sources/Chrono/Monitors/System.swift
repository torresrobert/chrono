import Darwin
import Foundation

enum Sysctl {
    static func int(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        switch size {
        case 4: return Int(Int32(truncatingIfNeeded: value))
        default: return Int(value)
        }
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    static func value<T>(_ name: String, as _: T.Type) -> T? {
        let ptr = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { ptr.deallocate() }
        var size = MemoryLayout<T>.size
        guard sysctlbyname(name, ptr, &size, nil, 0) == 0 else { return nil }
        return ptr.pointee
    }
}

enum MachTime {
    /// Multiplier converting mach absolute time units to nanoseconds.
    static let nanosPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()
}

struct SystemInfo {
    let model: String
    let chip: String
    let memory: UInt64
    let osVersion: String

    static let current = SystemInfo(
        model: Sysctl.string("hw.model") ?? "Mac",
        chip: Sysctl.string("machdep.cpu.brand_string") ?? "Unknown",
        memory: UInt64(Sysctl.int("hw.memsize") ?? 0),
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString
    )

    static var bootDate: Date? {
        guard let tv = Sysctl.value("kern.boottime", as: timeval.self) else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }
}
