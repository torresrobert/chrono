import AppKit
import SwiftUI

/// How the menu bar items are inked. Monochrome renders a template image that macOS tints to
/// match the menu bar; color renders the final pixels, so it needs to know the menu bar's appearance.
struct MenuBarInk: Equatable {
    var colored: Bool
    var dark: Bool

    static let template = MenuBarInk(colored: false, dark: false)

    var text: Color { colored && dark ? .white : .black }

    /// A data color (graphs, rates), resolved for the menu bar's appearance.
    func data(_ color: Color) -> Color { colored ? color.resolved(dark: dark) : .black }

    /// Status tones, tuned for contrast against a bare menu bar rather than a card.
    func status(_ level: StatusLevel) -> Color {
        guard colored else { return .black }
        switch level {
        case .normal: return dark ? Color(hex: 0x4ADE80) : Color(hex: 0x15803D)
        case .elevated: return dark ? Color(hex: 0xFBBF24) : Color(hex: 0xB45309)
        case .critical: return dark ? Color(hex: 0xF87171) : Color(hex: 0xDC2626)
        }
    }

    /// Text that stays neutral until a reading needs attention.
    func alert(_ level: StatusLevel) -> Color { level == .normal ? text : status(level) }
}

/// The same thresholds the panels use (`Theme.load`, `Theme.temperature`, memory pressure).
enum StatusLevel {
    case normal, elevated, critical

    init(load fraction: Double) {
        self = fraction < 0.6 ? .normal : fraction < 0.85 ? .elevated : .critical
    }

    init(celsius: Double) {
        self = celsius < 75 ? .normal : celsius < 90 ? .elevated : .critical
    }

    init(pressure: MemoryPressure) {
        switch pressure {
        case .normal: self = .normal
        case .warning: self = .elevated
        case .critical: self = .critical
        }
    }

    init(battery: BatterySample) {
        if battery.isCharging || battery.level >= 0.2 { self = .normal }
        else { self = battery.level >= 0.1 ? .elevated : .critical }
    }
}

/// What's drawn in the menu bar for each module.
struct MenuBarLabel: View {
    let module: Module
    let store: Store
    let showLabels: Bool
    var ink: MenuBarInk = .template

    var body: some View {
        HStack(spacing: 3) {
            switch module {
            case .cpu:
                MiniGraph(values: store.cpuHistory.values.suffix(18), color: ink.data(Series.primary), frame: ink.text)
                value(caption: "CPU", Format.percent(store.cpu.total), width: 30,
                      color: ink.alert(StatusLevel(load: store.cpu.total)))
            case .gpu:
                MiniGraph(values: store.gpuHistory.values.suffix(18), color: ink.data(Series.secondary), frame: ink.text)
                value(caption: "GPU", Format.percent(store.gpu.utilization), width: 30,
                      color: ink.alert(StatusLevel(load: store.gpu.utilization)))
            case .memory:
                let pressure = StatusLevel(pressure: store.memory.pressure)
                Ring(fraction: store.memory.usedFraction, color: ink.status(pressure), track: ink.text)
                value(caption: "MEM", Format.percent(store.memory.usedFraction), width: 30, color: ink.alert(pressure))
            case .disk:
                StackedRates(top: ("R", store.disk.readRate, ink.data(Series.tertiary)),
                             bottom: ("W", store.disk.writeRate, ink.data(Series.secondary)), text: ink.text)
            case .network:
                StackedRates(top: ("↑", store.network.upRate, ink.data(Series.secondary)),
                             bottom: ("↓", store.network.downRate, ink.data(Series.tertiary)), text: ink.text)
            case .sensors:
                if let temp = store.sensors.cpu {
                    let level = StatusLevel(celsius: temp)
                    Image(systemName: "thermometer.medium").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ink.status(level))
                    value(caption: "CPU", Format.temperature(temp), width: 30, color: ink.alert(level))
                } else {
                    Image(systemName: "thermometer.medium").foregroundStyle(ink.text)
                }
            case .battery:
                if let battery = store.battery {
                    let level = StatusLevel(battery: battery)
                    Image(systemName: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent")
                        .font(.system(size: 13))
                        .foregroundStyle(battery.isCharging || level != .normal ? ink.status(level) : ink.text)
                    value(caption: "BAT", Format.percent(battery.level), width: 30, color: ink.alert(level))
                } else {
                    Image(systemName: "powerplug").foregroundStyle(ink.text)
                }
            }
        }
        .frame(height: 22)
        .padding(.horizontal, 1)
    }

    /// Everything the label draws, as a string; equal signatures render identical images.
    var signature: String {
        let graph = { (h: History) in h.values.suffix(18).map { String(Int(min(1, $0) * 30)) }.joined(separator: ",") }
        let body: String
        switch module {
        case .cpu: body = Format.percent(store.cpu.total) + graph(store.cpuHistory)
        case .gpu: body = Format.percent(store.gpu.utilization) + graph(store.gpuHistory)
        case .memory: body = String(format: "%.3f", store.memory.usedFraction) + store.memory.pressure.rawValue
        case .disk: body = Format.shortRate(store.disk.readRate) + Format.shortRate(store.disk.writeRate)
        case .network: body = Format.shortRate(store.network.upRate) + Format.shortRate(store.network.downRate)
        case .sensors: body = store.sensors.cpu.map { Format.temperature($0) + "\(StatusLevel(celsius: $0))" } ?? "-"
        case .battery: body = store.battery.map { Format.percent($0.level) + "\($0.isCharging)" } ?? "-"
        }
        return "\(showLabels)|\(ink.colored)|\(ink.dark)|\(NSScreen.main?.backingScaleFactor ?? 2)|" + body
    }

    @ViewBuilder
    private func value(caption: String, _ text: String, width: CGFloat, color: Color) -> some View {
        if showLabels {
            VStack(alignment: .leading, spacing: -2) {
                Text(caption).font(.system(size: 7.5, weight: .bold)).foregroundStyle(ink.text.opacity(0.75))
                Text(text).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(color)
            }
            .frame(width: width, alignment: .leading)
        } else {
            Text(text).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(color)
                .frame(width: width + 2, alignment: .trailing)
        }
    }
}

private struct MiniGraph: View {
    let values: ArraySlice<Double>
    let color: Color
    let frame: Color

    var body: some View {
        let count = 18
        let padded = Array(repeating: 0.0, count: max(0, count - values.count)) + values
        HStack(alignment: .bottom, spacing: 0.5) {
            ForEach(Array(padded.enumerated()), id: \.offset) { _, v in
                Rectangle().fill(color).frame(width: 1, height: max(0.5, 15 * min(1, v)))
            }
        }
        .frame(width: CGFloat(count) * 1.5, height: 15, alignment: .bottom)
        .padding(1)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(frame.opacity(0.35), lineWidth: 0.75))
    }
}

private struct Ring: View {
    let fraction: Double
    let color: Color
    let track: Color

    var body: some View {
        ZStack {
            Circle().stroke(track.opacity(0.25), lineWidth: 2.5)
            Circle().trim(from: 0, to: fraction).stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 13, height: 13)
    }
}

private struct StackedRates: View {
    let top: (String, Double, Color)
    let bottom: (String, Double, Color)
    let text: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: -1.5) {
            row(top)
            row(bottom)
        }
        .font(.system(size: 9, weight: .semibold).monospacedDigit())
        .frame(width: 58, alignment: .trailing)
    }

    private func row(_ item: (String, Double, Color)) -> some View {
        HStack(spacing: 2) {
            Text(Format.shortRate(item.1)).foregroundStyle(text)
            Text(item.0).foregroundStyle(item.2).frame(width: 7)
        }
    }
}

@MainActor
enum MenuBarRenderer {
    static func image(for module: Module, store: Store, showLabels: Bool, ink: MenuBarInk = .template) -> NSImage? {
        let renderer = ImageRenderer(content: MenuBarLabel(module: module, store: store, showLabels: showLabels, ink: ink))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = !ink.colored
        return image
    }
}
