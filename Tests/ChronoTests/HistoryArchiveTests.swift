import Foundation
import Testing
@testable import Chrono

struct HistoryArchiveTests {
    @Test func foldsSamplesIntoMinutesWithAverageAndPeak() {
        var tier = Tier(width: 60, retention: 3600)
        #expect(tier.add(Bucket(value: 0.2, at: 120)) == nil)
        #expect(tier.add(Bucket(value: 0.8, at: 150)) == nil)
        let closed = tier.add(Bucket(value: 0.5, at: 185))
        #expect(closed?.start == 120)
        #expect(closed?.count == 2)
        #expect(closed?.peak == 0.8)
        #expect(abs((closed?.average ?? 0) - 0.5) < 1e-9)
        #expect(tier.buckets(since: 0).map(\.start) == [120, 180])
    }

    @Test func rollsMinutesIntoQuarterHours() {
        var history = MetricHistory()
        // 20 minutes of one sample per minute, value = minute index; one 1.0 spike.
        for minute in 0..<20 { history.record(minute == 7 ? 1.0 : 0.1, at: 900 * 10 + minute * 60) }
        let quarter = history.quarterHours.buckets(since: 0)
        #expect(quarter.first?.start == 9000)
        #expect(quarter.first?.count == 15)
        #expect(quarter.first?.peak == 1.0)
    }

    @Test func dropsBucketsPastRetention() {
        var tier = Tier(width: 60, retention: 600)
        for minute in 0..<30 { tier.add(Bucket(value: 1, at: minute * 60)) }
        let starts = tier.buckets(since: 0).map(\.start)
        #expect(starts.first! >= 29 * 60 - 600)
        #expect(starts.last == 29 * 60)
    }

    @Test func toleratesTheClockGoingBackwards() {
        var tier = Tier(width: 60, retention: 3600)
        tier.add(Bucket(value: 1, at: 600))
        tier.add(Bucket(value: 1, at: 660))
        tier.add(Bucket(value: 1, at: 300))  // clock set back
        tier.add(Bucket(value: 1, at: 720))
        let starts = tier.buckets(since: 0).map(\.start)
        #expect(starts == starts.sorted())
        #expect(tier.buckets(since: 0).reduce(0) { $0 + $1.count } == 4)
    }

    @Test func downsamplesWithWeightedAverages() {
        let buckets = [Bucket(start: 0, sum: 3, count: 3, peak: 2), Bucket(start: 60, sum: 1, count: 1, peak: 1),
                       Bucket(start: 600, sum: 5, count: 1, peak: 5)]
        let wide = Bucket.downsample(buckets, width: 600)
        #expect(wide.map(\.start) == [0, 600])
        #expect(wide[0].average == 1)
        #expect(wide[0].peak == 2)
    }

    @Test func roundTripsThroughStorage() throws {
        var history = MetricHistory()
        let base = 1_800_000_000
        for i in 0..<200 { history.record(Double(i % 17) * 1_000_000, at: base + i * 20) }
        let data = try PropertyListEncoder().encode(history)
        let decoded = try PropertyListDecoder().decode(MetricHistory.self, from: data)
        let before = history.minutes.buckets(since: 0), after = decoded.minutes.buckets(since: 0)
        #expect(before.map(\.start) == after.map(\.start))
        #expect(before.map(\.count) == after.map(\.count))
        for (a, b) in zip(before, after) {
            #expect(abs(a.average - b.average) <= a.average * 1e-6)
            #expect(abs(a.peak - b.peak) <= a.peak * 1e-6)
        }
    }

    @Test @MainActor func archiveServesRangesAndPersists() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("chrono-history-\(UUID()).plist")
        defer { try? FileManager.default.removeItem(at: file) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let archive = HistoryArchive(file: file, saves: true)
        for i in 0..<(3 * 60) {
            archive.record([.cpu: 0.25, .temperature: 50], at: now.addingTimeInterval(TimeInterval(i * 60 - 3 * 3600)))
        }
        #expect(archive.series(.cpu, range: .live, now: now).isEmpty)
        #expect(archive.series(.cpu, range: .hour, now: now).count >= 59)
        #expect(archive.series(.cpu, range: .day, now: now).count <= 144)
        #expect(!archive.series(.temperature, range: .week, now: now).isEmpty)

        archive.save(synchronously: true)
        let reloaded = HistoryArchive(file: file)
        #expect(reloaded.series(.cpu, range: .day, now: now) == archive.series(.cpu, range: .day, now: now))
    }
}
