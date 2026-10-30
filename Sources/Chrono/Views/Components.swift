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

/// Center-tach dial, after the app icon: a dark outer track with white major and fine yellow
/// minor ticks, an accent-colored ring, and a black center holding the readout. A yellow needle
/// sweeps 300°; ticks past `redline` turn red. The readout stays white until the reading needs
/// attention (`level`, defaulting to the load thresholds), then turns amber or red.
struct DialGauge: View {
    let fraction: Double
    let label: String
    var redline: Double = 0.85
    var level: StatusLevel?
    var size: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let needle = Color(hex: 0xE8D21C)
    private static let redlineColor = Color(hex: 0xE3213F)
    private var clamped: Double { min(1, max(0, fraction)) }

    private var readoutColor: Color {
        switch level ?? StatusLevel(load: clamped) {
        case .normal: Color(hex: 0xF3F4F6)
        case .elevated: Color(hex: 0xFBBF24)
        case .critical: Color(hex: 0xF87171)
        }
    }

    var body: some View {
        let r = size / 2
        ZStack {
            Canvas { context, canvas in
                let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                func disc(_ radius: CGFloat) -> Path {
                    Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
                }
                // Value 0...1 → screen point; 0 at about 8 o'clock, 1 at about 4 o'clock.
                func point(_ v: Double, _ radius: CGFloat) -> CGPoint {
                    let theta = (240 - 300 * v) * .pi / 180
                    return CGPoint(x: c.x + cos(theta) * radius, y: c.y - sin(theta) * radius)
                }
                func tick(_ v: Double, _ r0: CGFloat, _ r1: CGFloat, _ width: CGFloat, _ color: Color) {
                    var path = Path()
                    path.move(to: point(v, r0))
                    path.addLine(to: point(v, r1))
                    context.stroke(path, with: .color(color), lineWidth: width)
                }

                // Bezel and outer track.
                context.fill(disc(r), with: .linearGradient(
                    Gradient(colors: [Color(hex: 0x8A9099), Color(hex: 0x2A2E35), Color(hex: 0x4A4F57)]),
                    startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)))
                context.fill(disc(r - 1.5), with: .color(Color(hex: 0x111317)))

                // Ticks: fine yellow minors, white majors, red past the redline.
                for i in 0...20 {
                    let v = Double(i) / 20
                    let major = i % 2 == 0
                    let color = v > redline + 0.001 ? Self.redlineColor
                        : major ? Color(hex: 0xF3F4F6) : Self.needle.opacity(0.75)
                    tick(v, r * 0.92, major ? r * 0.78 : r * 0.84, major ? 1.4 : 0.9, color)
                }
                if redline < 1 {
                    var band = Path()
                    band.addArc(center: c, radius: r * 0.9, startAngle: .degrees(-(240 - 300 * redline)),
                                endAngle: .degrees(-(240 - 300)), clockwise: false)
                    context.stroke(band, with: .color(Self.redlineColor), lineWidth: 1.6)
                }

                // Accent ring and black center.
                context.fill(disc(r * 0.74), with: .color(Settings.shared.accent.deep))
                context.fill(disc(r * 0.56), with: .radialGradient(
                    Gradient(colors: [Color(hex: 0x1A1D23), Color(hex: 0x050608)]),
                    center: CGPoint(x: c.x, y: c.y - r * 0.15), startRadius: 0, endRadius: r * 0.6))
            }

            DialNeedle(length: r * 0.86, tail: r * 0.16, base: r * 0.07)
                .fill(Self.needle)
                .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
                .rotationEffect(.degrees(-150 + 300 * clamped))
                .animation(reduceMotion ? nil : Theme.ease(0.35), value: clamped)

            Circle()
                .fill(LinearGradient(colors: [.white, Color(hex: 0xB8BEC7), Color(hex: 0x6B7280)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: r * 0.2, height: r * 0.2)
                .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)

            // Readout above the needle, like the car's digital window, so it never gets covered.
            Text(label)
                .font(.system(size: size * 0.17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(readoutColor)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, 2.5)
                .background(RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Color(hex: 0x07080B).opacity(0.9)))
                .frame(maxWidth: r * 1.0)
                .offset(y: r * 0.32)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}

/// A tapered needle pointing straight up from the center of its frame, with a short tail.
private struct DialNeedle: Shape {
    let length: CGFloat
    let tail: CGFloat
    let base: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: CGPoint(x: c.x - base, y: c.y + tail))
        path.addLine(to: CGPoint(x: c.x - base * 0.3, y: c.y - length))
        path.addLine(to: CGPoint(x: c.x + base * 0.3, y: c.y - length))
        path.addLine(to: CGPoint(x: c.x + base, y: c.y + tail))
        path.closeSubpath()
        return path
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
                        AppIcon(pid: process.pid, isSimulator: process.isSimulator)
                        Text(process.name).lineLimit(1).truncationMode(.tail)
                        if process.isSimulator { SimulatorBadge() }
                        Spacer(minLength: 8)
                        Text(value(process)).monospacedDigit().foregroundStyle(Theme.textSecondary)
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }
}

/// Marks a process that belongs to a running Simulator device, not to macOS itself.
private struct SimulatorBadge: View {
    var body: some View {
        Text("Simulator")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Theme.border))
            .fixedSize()
            .accessibilityLabel("Running in Simulator")
    }
}

private struct AppIcon: View {
    let pid: pid_t
    var isSimulator = false

    var body: some View {
        if isSimulator {
            Image(systemName: "iphone").font(.system(size: 10)).frame(width: 15, height: 15)
                .foregroundStyle(Theme.textSecondary)
        } else if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            Image(nsImage: icon).resizable().frame(width: 15, height: 15)
        } else {
            Image(systemName: "terminal").font(.system(size: 9)).frame(width: 15, height: 15)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
