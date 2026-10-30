import Foundation
import Testing
@testable import Chrono

struct TerminalTests {
    @Test func drawsBrailleAreaFromTheBottomUp() {
        // Two rows = eight dots tall. Left column full, right column half.
        let rows = TerminalChart.area([1.0, 0.5], rows: 2)
        #expect(rows == ["⡇", "⣿"])
        // Zero and gaps leave blank cells; any value above zero shows a dot.
        #expect(TerminalChart.area([0, nil, 0.01, 0], rows: 1) == [" ⡀"])
    }

    @Test func spreadsBucketsOverColumnsKeepingSpikes() {
        let start = Date(timeIntervalSince1970: 0), end = Date(timeIntervalSince1970: 400)
        let buckets = [
            Bucket(start: 0, sum: 0.2, count: 1, peak: 0.2),
            Bucket(start: 100, sum: 0.9, count: 1, peak: 0.9),
            // Nothing for 200..<300: a gap.
            Bucket(start: 300, sum: 0.4, count: 2, peak: 0.6),
        ]
        let columns = TerminalChart.columns(buckets, width: 100, from: start, to: end, count: 4)
        #expect(columns == [0.2, 0.9, nil, 0.2])
        // Fewer columns than buckets: each takes the highest it overlaps.
        #expect(TerminalChart.columns(buckets, width: 100, from: start, to: end, count: 2) == [0.9, 0.2])
        #expect(TerminalChart.columns(buckets, \.peak, width: 100, from: start, to: end, count: 2) == [0.9, 0.6])
    }

    @Test func rightAlignsTheLiveWindow() {
        // Half full: the left half is empty, the newest sample sits at the right edge.
        #expect(TerminalChart.columns(live: [0.1, 0.3], capacity: 4, count: 4) == [nil, nil, 0.1, 0.3])
        #expect(TerminalChart.columns(live: [0.1, 0.5, 0.2, 0.3], capacity: 4, count: 2) == [0.5, 0.3])
        #expect(TerminalChart.columns(live: [0.4], capacity: 2, count: 4) == [nil, nil, 0.4, 0.4])
    }

    @Test func metersFillInHalfCells() {
        #expect(TerminalChart.meter(0.5, width: 4) == ("━━", "━━"))
        #expect(TerminalChart.meter(0.25, width: 2) == ("╸", "━"))
        #expect(TerminalChart.meter(1.5, width: 3) == ("━━━", ""))
    }

    @Test func clipsStyledLinesToTheWidth() {
        var line = Line("CPU", .strong)
        line.pad(to: 6)
        line.add("12%")
        #expect(line.width == 9)
        // NO_COLOR drops colors but keeps bold.
        #expect(line.rendered(width: 5, colors: .none) == "\u{1B}[1mCPU\u{1B}[0m  ")
        #expect(line.rendered(width: 20, colors: .palette) == "\u{1B}[1mCPU\u{1B}[0m   12%")
        line.trailing("now", at: 20)
        #expect(line.text.hasSuffix("12%        now"))
        // Doesn't overlap what's already there.
        line.trailing("too long", at: 22)
        #expect(line.width == 20)
    }

    @Test func mapsColorsToThePalette() {
        #expect(Style.nearestPaletteIndex(255, 0, 0) == 196)
        #expect(Style.nearestPaletteIndex(0x4B, 0x55, 0x63) == 240)
        #expect(Style(color: 0x60A5FA).escape(.trueColor) == "\u{1B}[38;2;96;165;250m")
        #expect(Style(color: 0x60A5FA, bold: true).escape(.none) == "\u{1B}[1m")
        #expect(TerminalPalette.dimmed(0xFFFFFF, by: 0.5) == 0x808080)
    }

    @Test func truncatesNamesWithAnEllipsis() {
        #expect(Dashboard.fit("Google Chrome Helper", width: 10) == "Google Ch…")
        #expect(Dashboard.fit("Safari", width: 10) == "Safari")
    }
}
