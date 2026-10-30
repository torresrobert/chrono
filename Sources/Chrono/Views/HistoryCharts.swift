import Charts
import SwiftUI

struct MetricSeries: Identifiable {
    let metric: Metric
    let name: String
    let color: Color
    var id: Metric { metric }
}

/// A panel's history chart: the live window, or a longer range from the archive.
/// The range is shared across panels (`Store.chartRange`).
struct MetricChart: View {
    let store: Store
    let series: [MetricSeries]
    /// Fixed upper bound (e.g. 1.0 for percentages); nil scales to the data.
    var maxValue: Double?
    var height: CGFloat = 64
    /// Shows the range picker. Secondary charts in a panel follow the main one's range.
    var picker = true
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if picker { RangePicker(selection: Bindable(store).chartRange) }
            if store.chartRange == .live {
                HistoryChart(series: series.map {
                    HistorySeries(name: $0.name, values: store.liveHistory($0.metric).values, color: $0.color)
                }, maxValue: maxValue, height: height)
            } else {
                let now = Date()
                let data = series.map { ($0, store.archive.series($0.metric, range: store.chartRange, now: now)) }
                TimelineChart(data: data, range: store.chartRange, now: now, maxValue: maxValue, height: height)
                if data.contains(where: { !$0.1.isEmpty }) {
                    VStack(spacing: 4) {
                        ForEach(data, id: \.0.id) { series, buckets in
                            let count = buckets.reduce(0) { $0 + $1.count }
                            let average = count > 0 ? buckets.reduce(0) { $0 + $1.sum } / Double(count) : 0
                            let peak = buckets.map(\.peak).max() ?? 0
                            StatRow(label: series.name, value: "\(format(average)) avg · \(format(peak)) peak",
                                    color: data.count > 1 ? series.color : nil)
                        }
                    }
                }
            }
        }
    }
}

private struct RangePicker: View {
    @Binding var selection: HistoryRange
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistoryRange.allCases) { range in
                Button {
                    withAnimation(reduceMotion ? nil : Theme.ease()) { selection = range }
                } label: {
                    Text(range.title)
                        .font(.system(size: 10.5, weight: selection == range ? .semibold : .medium))
                        .foregroundStyle(selection == range ? Theme.textPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3.5)
                        .background {
                            if selection == range {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.surface.opacity(0.9))
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == range ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(Theme.border.opacity(0.7)))
    }
}

/// Archive chart over real time: the line is the average, the shaded area reaches up to the peak.
/// Time when Chrono wasn't running (asleep, quit) is left as a gap rather than drawn across.
private struct TimelineChart: View {
    let data: [(MetricSeries, [Bucket])]
    let range: HistoryRange
    let now: Date
    var maxValue: Double?
    var height: CGFloat

    private struct Point: Identifiable {
        let id: String
        let segment: String
        let date: Date
        let average: Double
        let peak: Double
        let color: Color
    }

    private var points: [Point] {
        let gap = range.pointWidth * 2
        return data.flatMap { series, buckets in
            var segment = 0
            var previous: Int?
            return buckets.map { bucket in
                if let previous, bucket.start - previous > gap { segment += 1 }
                previous = bucket.start
                return Point(id: "\(series.name)-\(bucket.start)", segment: "\(series.name)-\(segment)",
                             date: bucket.date.addingTimeInterval(TimeInterval(range.pointWidth) / 2),
                             average: bucket.average, peak: bucket.peak, color: series.color)
            }
        }
    }

    private var upper: Double {
        if let maxValue { return maxValue }
        return max((data.flatMap { $0.1.map(\.peak) }.max() ?? 0) * 1.15, 1)
    }

    private var labelFormat: Date.FormatStyle {
        switch range {
        case .live, .hour: .dateTime.hour().minute()
        case .day: .dateTime.hour()
        case .week: .dateTime.weekday(.abbreviated)
        case .month: .dateTime.month(.abbreviated).day()
        }
    }

    /// Round-time ticks (every 15 min, 6 h, 2 days, a week), kept clear of the edges so labels aren't clipped.
    private func ticks(from start: Date, to end: Date) -> [Date] {
        let calendar = Calendar.current
        let margin = end.timeIntervalSince(start) * 0.12
        let (component, step): (Calendar.Component, Int) = switch range {
        case .live, .hour: (.minute, 15)
        case .day: (.hour, 6)
        case .week: (.day, 2)
        case .month: (.day, 7)
        }
        var date = calendar.dateInterval(of: component == .minute ? .hour : .day, for: start)?.start ?? start
        var result: [Date] = []
        var index = 0
        while date <= end {
            let value = component == .day ? index : calendar.component(component, from: date)
            if value % step == 0, date >= start.addingTimeInterval(margin), date <= end.addingTimeInterval(-margin) {
                result.append(date)
            }
            index += 1
            date = calendar.date(byAdding: component, value: 1, to: date) ?? end.addingTimeInterval(1)
        }
        return result
    }

    var body: some View {
        let points = points
        let start = now.addingTimeInterval(-TimeInterval(range.span ?? 0))
        Group {
            if points.isEmpty {
                Text("Collecting history. Check back in a few minutes.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: height + 14)
            } else {
                Chart(points) { point in
                    AreaMark(x: .value("Time", point.date), yStart: .value("Floor", 0), yEnd: .value("Peak", point.peak),
                             series: .value("Series", point.segment))
                        .foregroundStyle(point.color.opacity(0.22))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", point.date), y: .value("Average", point.average),
                             series: .value("Series", point.segment))
                        .foregroundStyle(point.color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                }
                .chartLegend(.hidden)
                .chartXScale(domain: start...now)
                .chartYScale(domain: 0...upper)
                .chartXAxis {
                    AxisMarks(values: ticks(from: start, to: now)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(Theme.border)
                        AxisValueLabel(format: labelFormat)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(Theme.border)
                    }
                }
                .frame(height: height + 14)
            }
        }
        .appCard(padding: 8)
    }
}
