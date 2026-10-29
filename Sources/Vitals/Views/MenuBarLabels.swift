import AppKit
import SwiftUI

/// What's drawn in the menu bar for each module. Rendered to a template image so macOS tints
/// it to match the menu bar (light, dark, tinted wallpapers).
struct MenuBarLabel: View {
    let module: Module
    let store: Store
    let showLabels: Bool

    var body: some View {
        HStack(spacing: 3) {
            switch module {
            case .cpu:
                MiniGraph(values: store.cpuHistory.values.suffix(18))
                value(caption: "CPU", Format.percent(store.cpu.total), width: 30)
            case .gpu:
                MiniGraph(values: store.gpuHistory.values.suffix(18))
                value(caption: "GPU", Format.percent(store.gpu.utilization), width: 30)
            case .memory:
                Ring(fraction: store.memory.usedFraction)
                value(caption: "MEM", Format.percent(store.memory.usedFraction), width: 30)
            case .disk:
                StackedRates(top: ("R", store.disk.readRate), bottom: ("W", store.disk.writeRate))
            case .network:
                StackedRates(top: ("↑", store.network.upRate), bottom: ("↓", store.network.downRate))
            case .sensors:
                if let temp = store.sensors.cpu {
                    Image(systemName: "thermometer.medium").font(.system(size: 12, weight: .medium))
                    value(caption: "CPU", Format.temperature(temp), width: 30)
                } else {
                    Image(systemName: "thermometer.medium")
                }
            case .battery:
                if let battery = store.battery {
                    Image(systemName: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent")
                        .font(.system(size: 13))
                    value(caption: "BAT", Format.percent(battery.level), width: 30)
                } else {
                    Image(systemName: "powerplug")
                }
            }
        }
        .foregroundStyle(.black)
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
        case .memory: body = String(format: "%.3f", store.memory.usedFraction)
        case .disk: body = Format.shortRate(store.disk.readRate) + Format.shortRate(store.disk.writeRate)
        case .network: body = Format.shortRate(store.network.upRate) + Format.shortRate(store.network.downRate)
        case .sensors: body = store.sensors.cpu.map { Format.temperature($0) } ?? "-"
        case .battery: body = store.battery.map { Format.percent($0.level) + "\($0.isCharging)" } ?? "-"
        }
        return "\(showLabels)|\(NSScreen.main?.backingScaleFactor ?? 2)|" + body
    }

    @ViewBuilder
    private func value(caption: String, _ text: String, width: CGFloat) -> some View {
        if showLabels {
            VStack(alignment: .leading, spacing: -2) {
                Text(caption).font(.system(size: 7.5, weight: .bold)).opacity(0.75)
                Text(text).font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            .frame(width: width, alignment: .leading)
        } else {
            Text(text).font(.system(size: 12, weight: .medium).monospacedDigit())
                .frame(width: width + 2, alignment: .trailing)
        }
    }
}

private struct MiniGraph: View {
    let values: ArraySlice<Double>

    var body: some View {
        let count = 18
        let padded = Array(repeating: 0.0, count: max(0, count - values.count)) + values
        HStack(alignment: .bottom, spacing: 0.5) {
            ForEach(Array(padded.enumerated()), id: \.offset) { _, v in
                Rectangle().frame(width: 1, height: max(0.5, 15 * min(1, v)))
            }
        }
        .frame(width: CGFloat(count) * 1.5, height: 15, alignment: .bottom)
        .padding(1)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(lineWidth: 0.75).opacity(0.35))
    }
}

private struct Ring: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(lineWidth: 2.5).opacity(0.25)
            Circle().trim(from: 0, to: fraction).stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 13, height: 13)
    }
}

private struct StackedRates: View {
    let top: (String, Double)
    let bottom: (String, Double)

    var body: some View {
        VStack(alignment: .trailing, spacing: -1.5) {
            row(top)
            row(bottom)
        }
        .font(.system(size: 9, weight: .semibold).monospacedDigit())
        .frame(width: 58, alignment: .trailing)
    }

    private func row(_ item: (String, Double)) -> some View {
        HStack(spacing: 2) {
            Text(Format.shortRate(item.1))
            Text(item.0).frame(width: 7)
        }
    }
}

@MainActor
enum MenuBarRenderer {
    static func image(for module: Module, store: Store, showLabels: Bool) -> NSImage? {
        let renderer = ImageRenderer(content: MenuBarLabel(module: module, store: store, showLabels: showLabels))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
    }
}
