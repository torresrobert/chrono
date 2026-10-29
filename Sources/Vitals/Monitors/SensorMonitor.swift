import CSensors
import Foundation

struct SensorGroup: Identifiable {
    let name: String
    let average: Double
    let maximum: Double
    let count: Int
    var id: String { name }
}

struct Fan: Identifiable {
    let index: Int
    let rpm: Double
    let minimum: Double
    let maximum: Double
    var id: Int { index }
    var fraction: Double { maximum > minimum ? max(0, min(1, (rpm - minimum) / (maximum - minimum))) : 0 }
}

struct SensorSample {
    var groups: [SensorGroup] = []
    var fans: [Fan] = []
    var systemPower: Double?   // watts

    var cpu: Double? { groups.first { $0.name == "CPU" }?.average }
    var gpu: Double? { groups.first { $0.name == "GPU" }?.average }
}

final class SensorMonitor {
    /// SMC temperature-key prefixes, in display order. Key layout differs per chip, so groups
    /// with no valid keys on this machine are simply dropped.
    private static let groupPrefixes: [(name: String, prefixes: [String])] = [
        ("CPU", ["Tp", "Te"]),
        ("GPU", ["Tg"]),
        ("Memory", ["Tm"]),
        ("SSD", ["TN"]),
        ("Airflow", ["TaF", "TaR"]),
        ("Battery", ["TB"]),
        ("Wireless", ["TW"]),
    ]

    private var groupKeys: [(name: String, keys: [String])] = []
    private let fanLimits: [(minimum: Double, maximum: Double)]
    private let hasSystemPower: Bool

    init() {
        smc_open()
        var buckets = [String: [String]]()
        let total = smc_key_count()
        var key = [CChar](repeating: 0, count: 5)
        var type = [CChar](repeating: 0, count: 5)
        for index in 0..<total {
            guard smc_key_at(index, &key, &type) == 0 else { continue }
            let name = String(cString: key)
            guard name.hasPrefix("T"),
                  let group = Self.groupPrefixes.first(where: { $0.prefixes.contains(where: name.hasPrefix) }),
                  let value = Self.read(name), value > 1, value < 130 else { continue }
            buckets[group.name, default: []].append(name)
        }
        // Desktops expose TB* keys too, but they aren't a battery there.
        if BatteryMonitor().sample() == nil { buckets["Battery"] = nil }
        // Each SMC read is an IOKit round trip and some groups have 80+ near-identical sensors,
        // so sample an evenly spread subset per group to keep a tick cheap.
        groupKeys = Self.groupPrefixes.compactMap { group in
            buckets[group.name].map { (group.name, Self.spread($0.sorted(), limit: Self.keysPerGroup)) }
        }
        fanLimits = (0..<Int(Self.read("FNum") ?? 0)).map { i in
            (Self.read("F\(i)Mn") ?? 0, Self.read("F\(i)Mx") ?? 0)
        }
        hasSystemPower = Self.read("PSTR") != nil
    }

    var hasFans: Bool { !fanLimits.isEmpty }

    func sample() -> SensorSample {
        var sample = SensorSample()
        for group in groupKeys {
            let values = group.keys.compactMap(Self.read).filter { $0 > 1 && $0 < 130 }
            guard !values.isEmpty else { continue }
            sample.groups.append(SensorGroup(name: group.name, average: values.reduce(0, +) / Double(values.count),
                                             maximum: values.max() ?? 0, count: values.count))
        }
        if sample.cpu == nil {
            // Fallback: HID die sensors are present on all Apple Silicon Macs.
            let dies = Self.hidTemperatures().filter { $0.name.contains("tdie") }.map(\.celsius)
            if !dies.isEmpty {
                sample.groups.insert(SensorGroup(name: "CPU", average: dies.reduce(0, +) / Double(dies.count),
                                                 maximum: dies.max() ?? 0, count: dies.count), at: 0)
            }
        }
        sample.fans = fanLimits.enumerated().compactMap { i, limits in
            Self.read("F\(i)Ac").map { Fan(index: i, rpm: $0, minimum: limits.minimum, maximum: limits.maximum) }
        }
        if hasSystemPower { sample.systemPower = Self.read("PSTR") }
        return sample
    }

    private static let keysPerGroup = 6

    private static func spread(_ keys: [String], limit: Int) -> [String] {
        guard keys.count > limit else { return keys }
        let step = Double(keys.count) / Double(limit)
        return (0..<limit).map { keys[Int(Double($0) * step)] }
    }

    private static func read(_ key: String) -> Double? {
        var value = 0.0
        return smc_read_double(key, &value) == 0 && value.isFinite ? value : nil
    }

    static func hidTemperatures() -> [(name: String, celsius: Double)] {
        var buffer = [hid_temperature_t](repeating: hid_temperature_t(), count: 256)
        let count = Int(hid_read_temperatures(&buffer, Int32(buffer.count)))
        return buffer.prefix(count).map { sensor in
            var sensor = sensor
            let name = withUnsafeBytes(of: &sensor.name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            return (name, sensor.celsius)
        }
    }
}
