import Foundation
import Observation
import ServiceManagement

enum Module: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, disk, network, sensors, battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .network: "Network"
        case .sensors: "Sensors"
        case .battery: "Battery"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "rectangle.3.group"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .sensors: "thermometer.medium"
        case .battery: "battery.75percent"
        }
    }

    static let defaults: Set<Module> = [.cpu, .memory, .network, .sensors]
}

@MainActor
@Observable
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    var enabled: Set<Module> {
        didSet { defaults.set(enabled.map(\.rawValue), forKey: "enabledModules"); onChange?() }
    }

    var interval: Double {
        didSet { defaults.set(interval, forKey: "interval"); onChange?() }
    }

    var fahrenheit: Bool {
        didSet { defaults.set(fahrenheit, forKey: "fahrenheit"); onChange?() }
    }

    var showLabels: Bool {
        didSet { defaults.set(showLabels, forKey: "showLabels"); onChange?() }
    }

    var accent: Accent {
        didSet { defaults.set(accent.rawValue, forKey: "accent") }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Chrono: launch at login change failed: \(error)")
            }
        }
    }

    @ObservationIgnored var onChange: (() -> Void)?

    private init() {
        if let saved = defaults.stringArray(forKey: "enabledModules") {
            enabled = Set(saved.compactMap(Module.init(rawValue:)))
        } else {
            enabled = Module.defaults
        }
        let savedInterval = defaults.double(forKey: "interval")
        interval = savedInterval > 0 ? savedInterval : 2
        fahrenheit = defaults.bool(forKey: "fahrenheit")
        showLabels = defaults.object(forKey: "showLabels") as? Bool ?? true
        accent = defaults.string(forKey: "accent").flatMap(Accent.init(rawValue:)) ?? .racingRed
    }

    func isEnabled(_ module: Module) -> Bool { enabled.contains(module) }

    func set(_ module: Module, enabled on: Bool) {
        if on { enabled.insert(module) } else { enabled.remove(module) }
    }
}
