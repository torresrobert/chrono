import Charts
import SwiftUI

enum Palette {
    static let user = Color(red: 0.24, green: 0.56, blue: 1.0)
    static let system = Color(red: 1.0, green: 0.42, blue: 0.29)
    static let app = Color(red: 0.24, green: 0.56, blue: 1.0)
    static let wired = Color(red: 1.0, green: 0.62, blue: 0.2)
    static let compressed = Color(red: 0.68, green: 0.45, blue: 0.98)
    static let cached = Color.secondary.opacity(0.45)
    static let upload = Color(red: 1.0, green: 0.37, blue: 0.55)
    static let download = Color(red: 0.2, green: 0.78, blue: 0.72)
    static let gpu = Color(red: 0.36, green: 0.82, blue: 0.42)
    static let heat = Color(red: 1.0, green: 0.55, blue: 0.2)
    static let power = Color(red: 1.0, green: 0.8, blue: 0.2)

    static func load(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: Color(red: 0.36, green: 0.82, blue: 0.42)
        case ..<0.85: Color(red: 1.0, green: 0.7, blue: 0.2)
        default: Color(red: 1.0, green: 0.33, blue: 0.3)
        }
    }

    static func pressure(_ p: MemoryPressure) -> Color {
        switch p {
        case .normal: load(0)
        case .warning: load(0.7)
        case .critical: load(1)
        }
    }
}

// MARK: - Layout

struct PanelHeader: View {
    let title: String
    let symbol: String
    let value: String
    var detail: String?
    var tint: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .labelStyle(.titleAndIcon)
            Spacer()
            if let detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
    }
}

struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var color: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let color {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

struct MeterBar: View {
    let fraction: Double
    var color: Color = .accentColor
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color)
                    .frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
                    .opacity(fraction > 0.001 ? 1 : 0)
            }
        }
        .frame(height: height)
    }
}

/// A horizontal bar split into colored segments (e.g. memory composition).
struct SegmentedBar: View {
    let segments: [(fraction: Double, color: Color)]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle().fill(segment.color)
                        .frame(width: max(0, geo.size.width * segment.fraction - 1.5))
                }
                Spacer(minLength: 0)
            }
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: height)
    }
}

// MARK: - Charts

struct HistorySeries: Identifiable {
    let name: String
    let values: [Double]
    let color: Color
    var id: String { name }
}

struct HistoryChart: View {
    let series: [HistorySeries]
    /// Fixed upper bound (e.g. 1.0 for percentages); nil scales to the data.
    var maxValue: Double?
    var height: CGFloat = 64
    var stacked = false

    private var upper: Double {
        if let maxValue { return maxValue }
        let peak = stacked
            ? zip(series.first?.values ?? [], series.dropFirst().first?.values ?? []).map(+).max() ?? 0
            : series.flatMap(\.values).max() ?? 0
        return max(peak * 1.15, 1)
    }

    var body: some View {
        Chart {
            ForEach(series) { s in
                let offset = History.capacity - s.values.count
                ForEach(Array(s.values.enumerated()), id: \.offset) { i, v in
                    AreaMark(x: .value("t", i + offset), y: .value(s.name, v), stacking: stacked ? .standard : .unstacked)
                        .foregroundStyle(by: .value("series", s.name))
                        .opacity(stacked ? 0.85 : 0.25)
                        .interpolationMethod(.monotone)
                    if !stacked {
                        LineMark(x: .value("t", i + offset), y: .value(s.name, v))
                            .foregroundStyle(by: .value("series", s.name))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.monotone)
                    }
                }
            }
        }
        .chartForegroundStyleScale(domain: series.map(\.name), range: series.map(\.color))
        .chartLegend(.hidden)
        .chartXScale(domain: 0...(History.capacity - 1))
        .chartYScale(domain: 0...upper)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }
        }
        .frame(height: height)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }
}

// MARK: - Processes

struct ProcessList: View {
    let processes: [ProcessUsage]
    let value: (ProcessUsage) -> String

    var body: some View {
        if processes.isEmpty {
            Text("Sampling…").font(.system(size: 12)).foregroundStyle(.tertiary)
        } else {
            VStack(spacing: 4) {
                ForEach(processes) { process in
                    HStack(spacing: 6) {
                        AppIcon(pid: process.pid)
                        Text(process.name).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(value(process)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }
}

private struct AppIcon: View {
    let pid: pid_t

    var body: some View {
        if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            Image(nsImage: icon).resizable().frame(width: 14, height: 14)
        } else {
            Image(systemName: "gearshape").font(.system(size: 10)).frame(width: 14, height: 14)
                .foregroundStyle(.tertiary)
        }
    }
}
