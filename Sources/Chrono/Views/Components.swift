import Charts
import SwiftUI

// MARK: - Layout

/// Panel title row: module name on the left, an instrument (dial or readout) on the right.
struct PanelHeader<Instrument: View>: View {
    let title: String
    let symbol: String
    var detail: String?
    @ViewBuilder var instrument: Instrument

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            instrument
        }
    }
}

extension PanelHeader where Instrument == Readout {
    init(title: String, symbol: String, value: String, detail: String? = nil, tint: Color? = nil) {
        self.init(title: title, symbol: symbol, detail: detail) { Readout(value: value, tint: tint) }
    }
}

/// A large numeric readout, for values that aren't a fraction of something (rates, watts).
struct Readout: View {
    let value: String
    var tint: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(value)
            .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(tint ?? Theme.textPrimary)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : Theme.ease(), value: value)
    }
}

/// Dash-style dial: a 270° sweep with tick marks, a value arc in the status color, and a
/// redline zone in the accent color near the top of the range.
struct DialGauge: View {
    let fraction: Double
    let label: String
    var redline: Double = 0.85
    var color: Color?
    var size: CGFloat = 58
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sweep = 0.75
    private var clamped: Double { min(1, max(0, fraction)) }

    var body: some View {
        let line = size * 0.085
        ZStack {
            // Ticks
            ForEach(0..<11) { i in
                Capsule()
                    .fill(Double(i) / 10 >= redline ? Theme.accent : Theme.textSecondary.opacity(0.45))
                    .frame(width: 1.2, height: i % 5 == 0 ? size * 0.09 : size * 0.05)
                    .offset(y: -size / 2 + size * 0.05)
                    .rotationEffect(.degrees(-135 + Double(i) * 27))
            }
            // Track and redline zone
            Circle().trim(from: 0, to: sweep)
                .stroke(Theme.border, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(size * 0.16)
            Circle().trim(from: sweep * redline, to: sweep)
                .stroke(Theme.accent.opacity(0.35), style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(size * 0.16)
            // Value
            Circle().trim(from: 0, to: max(0.001, sweep * clamped))
                .stroke(color ?? Theme.load(clamped), style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(size * 0.16)
                .animation(reduceMotion ? nil : Theme.ease(0.35), value: clamped)
            Text(label)
                .font(.system(size: size * 0.22, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, size * 0.2)
                .offset(y: size * 0.03)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}

/// Section with a torres-style overline label.
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
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var color: Color?
    var valueColor: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let color {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            }
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().foregroundStyle(valueColor ?? Theme.textPrimary)
        }
        .font(.system(size: 12))
    }
}

struct MeterBar: View {
    let fraction: Double
    var color: Color = Series.primary
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
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
            .background(Theme.border)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
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

    private var upper: Double {
        if let maxValue { return maxValue }
        return max((series.flatMap(\.values).max() ?? 0) * 1.15, 1)
    }

    var body: some View {
        Chart {
            ForEach(series) { s in
                let offset = History.capacity - s.values.count
                ForEach(Array(s.values.enumerated()), id: \.offset) { i, v in
                    AreaMark(x: .value("t", i + offset), y: .value(s.name, v), stacking: .unstacked)
                        .foregroundStyle(LinearGradient(colors: [s.color.opacity(0.35), s.color.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("t", i + offset), y: .value(s.name, v), series: .value("series", s.name))
                        .foregroundStyle(s.color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: 0...(History.capacity - 1))
        .chartYScale(domain: 0...upper)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(Theme.border)
            }
        }
        .frame(height: height)
        .appCard(padding: 8)
    }
}

// MARK: - Processes

struct ProcessList: View {
    let processes: [ProcessUsage]
    let value: (ProcessUsage) -> String

    var body: some View {
        if processes.isEmpty {
            Text("Sampling…").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        } else {
            VStack(spacing: 5) {
                ForEach(processes) { process in
                    HStack(spacing: 7) {
                        AppIcon(pid: process.pid)
                        Text(process.name).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(value(process)).monospacedDigit().foregroundStyle(Theme.textSecondary)
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
            Image(nsImage: icon).resizable().frame(width: 15, height: 15)
        } else {
            Image(systemName: "terminal").font(.system(size: 9)).frame(width: 15, height: 15)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
