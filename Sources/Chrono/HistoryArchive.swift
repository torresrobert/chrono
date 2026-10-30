import Foundation
import Observation

// Long-term history: every sample is folded into 1-minute buckets (kept a day) and those into
// 15-minute buckets (kept 30 days). Each bucket keeps the average and the peak, so a short spike
// still shows in a 30-day view. Saved to a small file in Application Support; never sent anywhere.

enum Metric: String, CaseIterable, Codable {
    case cpu, memory, gpu, upload, download, read, write, temperature, power
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case live, hour, day, week, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live"
        case .hour: "1H"
        case .day: "24H"
        case .week: "7D"
        case .month: "30D"
        }
    }

    /// Seconds covered; nil for the in-memory live window.
    var span: Int? {
        switch self {
        case .live: nil
        case .hour: 3600
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        }
    }

    /// Width of one plotted point, keeping every range under ~180 points.
    var pointWidth: Int {
        switch self {
        case .live, .hour: 60
        case .day: 600
        case .week: 3600
        case .month: 4 * 3600
        }
    }

    var usesQuarterHours: Bool { self == .week || self == .month }
}

struct Bucket: Equatable {
    var start: Int  // seconds since 1970, aligned to the bucket width
    var sum: Double
    var count: Int
    var peak: Double

    init(start: Int, sum: Double, count: Int, peak: Double) {
        self.start = start
        self.sum = sum
        self.count = count
        self.peak = peak
    }

    init(value: Double, at time: Int) {
        self.init(start: time, sum: value, count: 1, peak: value)
    }

    var average: Double { count > 0 ? sum / Double(count) : 0 }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(start)) }

    mutating func merge(_ other: Bucket) {
        sum += other.sum
        count += other.count
        peak = max(peak, other.peak)
    }

    static func align(_ time: Int, to width: Int) -> Int {
        time - ((time % width) + width) % width
    }

    /// Merges consecutive buckets into wider ones (weighted average, max peak).
    static func downsample(_ buckets: [Bucket], width: Int) -> [Bucket] {
        var result: [Bucket] = []
        for bucket in buckets {
            let start = align(bucket.start, to: width)
            if let last = result.last, last.start == start {
                result[result.count - 1].merge(bucket)
            } else {
                var widened = bucket
                widened.start = start
                result.append(widened)
            }
        }
        return result
    }
}

/// Fixed-width buckets, oldest first, kept for `retention` seconds.
struct Tier: Equatable {
    let width: Int
    let retention: Int
    private(set) var closed: [Bucket] = []
    private(set) var open: Bucket?

    init(width: Int, retention: Int) {
        self.width = width
        self.retention = retention
    }

    /// Adds to the bucket covering `incoming.start`. Returns the bucket this closes, if any.
    @discardableResult
    mutating func add(_ incoming: Bucket) -> Bucket? {
        var incoming = incoming
        incoming.start = Bucket.align(incoming.start, to: width)
        guard let current = open else {
            open = incoming
            return nil
        }
        if incoming.start <= current.start {
            // Same bucket, or the clock moved backwards: fold it into the open bucket.
            open?.merge(incoming)
            return nil
        }
        if let last = closed.last, current.start <= last.start {
            closed[closed.count - 1].merge(current)
        } else {
            closed.append(current)
        }
        open = incoming
        let cutoff = incoming.start - retention
        if let first = closed.first, first.start < cutoff {
            closed.removeFirst(closed.firstIndex { $0.start >= cutoff } ?? closed.count)
        }
        return current
    }

    /// Buckets starting at or after `time`, including the one still filling.
    func buckets(since time: Int) -> [Bucket] {
        var low = 0, high = closed.count
        while low < high {
            let mid = (low + high) / 2
            if closed[mid].start < time { low = mid + 1 } else { high = mid }
        }
        var result = Array(closed[low...])
        if let open, open.start >= Bucket.align(time, to: width) { result.append(open) }
        return result
    }
}

struct MetricHistory: Equatable, Codable {
    var minutes = Tier(width: 60, retention: 25 * 3600)
    var quarterHours = Tier(width: 900, retention: 31 * 86_400)

    mutating func record(_ value: Double, at time: Int) {
        if let minute = minutes.add(Bucket(value: value, at: time)) {
            quarterHours.add(minute)
        }
    }
}

// MARK: - Storage

/// Buckets are packed as 14 bytes each (start, average, peak, count) to keep the file small:
/// 9 metrics × (1,500 + 3,000) buckets is well under 1 MB.
extension Tier: Codable {
    private enum CodingKeys: String, CodingKey { case width, retention, closed, open }
    private static let referenceTime = 978_307_200  // 2001-01-01, so offsets fit in UInt32 until 2137
    private static let stride = 14

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decode(Int.self, forKey: .width)
        retention = try container.decode(Int.self, forKey: .retention)
        closed = Self.unpack(try container.decode(Data.self, forKey: .closed))
        open = Self.unpack(try container.decode(Data.self, forKey: .open)).first
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(retention, forKey: .retention)
        try container.encode(Self.pack(closed), forKey: .closed)
        try container.encode(Self.pack(open.map { [$0] } ?? []), forKey: .open)
    }

    private static func pack(_ buckets: [Bucket]) -> Data {
        var data = Data(capacity: buckets.count * stride)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        for bucket in buckets {
            append(UInt32(clamping: bucket.start - referenceTime))
            append(Float(bucket.average).bitPattern)
            append(Float(bucket.peak).bitPattern)
            append(UInt16(clamping: bucket.count))
        }
        return data
    }

    private static func unpack(_ data: Data) -> [Bucket] {
        data.withUnsafeBytes { raw in
            (0..<(raw.count / stride)).map { i in
                let offset = i * stride
                let start = Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
                let average = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self)))
                let peak = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self)))
                let count = Int(UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: offset + 12, as: UInt16.self)))
                return Bucket(start: start + referenceTime, sum: Double(average) * Double(count), count: count,
                              peak: Double(peak))
            }
        }
    }
}

@MainActor
@Observable
final class HistoryArchive {
    private(set) var metrics: [Metric: MetricHistory] = [:]

    @ObservationIgnored private let file: URL?
    @ObservationIgnored private let saves: Bool
    @ObservationIgnored private var lastSave = Date()
    @ObservationIgnored private let writer = DispatchQueue(label: "chrono.history", qos: .utility)

    nonisolated static let defaultFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("me.torresrobert.chrono", isDirectory: true)
        .appendingPathComponent("history.plist")

    private struct Stored: Codable {
        var version = 1
        var metrics: [String: MetricHistory]
    }

    /// - Parameters:
    ///   - file: where history is loaded from (and saved to, when `saves` is set); nil keeps it in memory.
    ///   - saves: only the running app writes; diagnostics modes read the same file without touching it.
    init(file: URL? = HistoryArchive.defaultFile, saves: Bool = false) {
        self.file = file
        self.saves = saves && file != nil
        if let file, let data = try? Data(contentsOf: file),
           let stored = try? PropertyListDecoder().decode(Stored.self, from: data), stored.version == 1 {
            metrics = Dictionary(uniqueKeysWithValues: stored.metrics.compactMap { key, value in
                Metric(rawValue: key).map { ($0, value) }
            })
        }
    }

    func record(_ values: [Metric: Double], at date: Date = Date()) {
        let time = Int(date.timeIntervalSince1970)
        for (metric, value) in values where value.isFinite {
            metrics[metric, default: MetricHistory()].record(value, at: time)
        }
        if saves, date.timeIntervalSince(lastSave) > 300 { save() }
    }

    /// Points for a chart, oldest first. Empty for `.live`, which comes from the in-memory window.
    func series(_ metric: Metric, range: HistoryRange, now: Date = Date()) -> [Bucket] {
        guard let span = range.span, let history = metrics[metric] else { return [] }
        let tier = range.usesQuarterHours ? history.quarterHours : history.minutes
        let since = Int(now.timeIntervalSince1970) - span
        return Bucket.downsample(tier.buckets(since: since), width: range.pointWidth)
    }

    /// Writes history to disk. `synchronously` is for app termination, when a queued write could be lost.
    func save(synchronously: Bool = false) {
        guard saves, let file else { return }
        lastSave = Date()
        let stored = Stored(metrics: Dictionary(uniqueKeysWithValues: metrics.map { ($0.key.rawValue, $0.value) }))
        let write: @Sendable () -> Void = {
            do {
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                let data = try encoder.encode(stored)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
            } catch {
                NSLog("Chrono: saving history failed: \(error)")
            }
        }
        if synchronously { write() } else { writer.async(execute: write) }
    }
}
