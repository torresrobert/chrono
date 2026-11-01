import Testing
@testable import Chrono

struct FormatTests {
    @Test func percentRounds() {
        #expect(Format.percent(0) == "0%")
        #expect(Format.percent(0.426) == "43%")
        #expect(Format.percent(1) == "100%")
    }

    @Test func memoryBytesUseBinaryUnits() {
        #expect(Format.bytes(512) == "512 B")
        #expect(Format.bytes(1536) == "1.5 KB")
        #expect(Format.bytes(UInt64(128) << 30) == "128 GB")
        #expect(Format.bytes(-5.0) == "0 B")
    }

    @Test func diskBytesUseDecimalUnits() {
        #expect(Format.diskBytes(Int64(2_000_000_000_000)) == "2.0 TB")
        #expect(Format.diskBytes(Int64(956_000_000_000)) == "956 GB")
    }

    @Test(arguments: [0.0, 999, 1023, 9_999, 123_456, 9_876_543, 1.5e9, 9.9e12])
    func menuBarRatesStayNarrow(rate: Double) {
        // The menu bar item has a fixed width; longer strings would clip.
        #expect(Format.shortRate(rate).count <= 8, "\(Format.shortRate(rate))")
    }

    @Test func shortRateUnits() {
        #expect(Format.shortRate(0) == "0 B/s")
        #expect(Format.shortRate(12 * 1024) == "12 KB/s")
        #expect(Format.shortRate(1.4 * 1024 * 1024) == "1.4 MB/s")
    }

    @Test func watts() {
        #expect(Format.watts(9.84) == "9.8 W")
        #expect(Format.watts(118.4) == "118 W")
    }

    @Test func megahertz() {
        #expect(Format.megahertz(338) == "338 MHz")
        #expect(Format.megahertz(1619.6) == "1,620 MHz")
    }

    @Test func minutes() {
        #expect(Format.minutes(125) == "2:05")
    }
}
