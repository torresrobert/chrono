import Foundation
import IOKit.ps

struct BatterySample {
    var level: Double = 0          // 0...1
    var isCharging = false
    var isPluggedIn = false
    var minutesRemaining: Int?
    var health: String?
}

final class BatteryMonitor {
    /// Returns nil on Macs without an internal battery.
    func sample() -> BatterySample? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            var sample = BatterySample()
            sample.level = max > 0 ? Double(current) / Double(max) : 0
            sample.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            sample.isPluggedIn = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let key = sample.isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            if let minutes = desc[key] as? Int, minutes > 0 { sample.minutesRemaining = minutes }
            sample.health = desc[kIOPSBatteryHealthKey] as? String
            return sample
        }
        return nil
    }
}
