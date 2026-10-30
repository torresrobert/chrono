import Darwin
import Foundation

/// How much color the terminal gets: 24-bit when it says so (`COLORTERM`), the xterm-256 palette
/// otherwise (tmux and SSH sessions often drop `COLORTERM`), none when `NO_COLOR` is set.
enum ColorMode {
    case none, palette, trueColor

    static let current: ColorMode = {
        let env = ProcessInfo.processInfo.environment
        if let noColor = env["NO_COLOR"], !noColor.isEmpty { return .none }
        let colorTerm = env["COLORTERM"]?.lowercased() ?? ""
        return colorTerm.contains("truecolor") || colorTerm.contains("24bit") ? .trueColor : .palette
    }()
}

struct Style: Equatable {
    var color: UInt?
    var bold = false

    static let plain = Style()
    static let strong = Style(bold: true)
    static let muted = Style(color: 0x9CA3AF)
    static let faint = Style(color: 0x4B5563)

    /// The menu bar's status tones for a dark background.
    static func status(_ level: StatusLevel) -> Style {
        switch level {
        case .normal: Style(color: 0x4ADE80)
        case .elevated: Style(color: 0xFBBF24)
        case .critical: Style(color: 0xF87171)
        }
    }

    /// Plain until a reading needs attention, like the menu bar values.
    static func alert(_ level: StatusLevel) -> Style { level == .normal ? .plain : status(level) }

    func escape(_ mode: ColorMode) -> String {
        var codes: [String] = bold ? ["1"] : []
        if let color {
            let r = Int((color >> 16) & 0xff), g = Int((color >> 8) & 0xff), b = Int(color & 0xff)
            switch mode {
            case .trueColor: codes.append("38;2;\(r);\(g);\(b)")
            case .palette: codes.append("38;5;\(Self.nearestPaletteIndex(r, g, b))")
            case .none: break
            }
        }
        return codes.isEmpty ? "" : "\u{1B}[" + codes.joined(separator: ";") + "m"
    }

    /// Closest xterm-256 color: the 6×6×6 cube or the gray ramp, whichever is nearer.
    static func nearestPaletteIndex(_ r: Int, _ g: Int, _ b: Int) -> Int {
        let levels = [0, 95, 135, 175, 215, 255]
        func level(_ c: Int) -> Int { levels.indices.min { abs(levels[$0] - c) < abs(levels[$1] - c) } ?? 0 }
        func distance(_ c: (Int, Int, Int)) -> Int { (c.0 - r) * (c.0 - r) + (c.1 - g) * (c.1 - g) + (c.2 - b) * (c.2 - b) }
        let (ri, gi, bi) = (level(r), level(g), level(b))
        let gray = max(0, min(23, ((r + g + b) / 3 - 3) / 10))
        let grayValue = 8 + 10 * gray
        return distance((levels[ri], levels[gi], levels[bi])) <= distance((grayValue, grayValue, grayValue))
            ? 16 + 36 * ri + 6 * gi + bi : 232 + gray
    }
}

/// One row of the screen, built from styled pieces and clipped to the terminal width when drawn.
/// Widths count characters; everything drawn here is one column wide.
struct Line {
    private(set) var pieces: [(text: String, style: Style)] = []
    private(set) var width = 0

    init(_ text: String = "", _ style: Style = .plain) {
        if !text.isEmpty { add(text, style) }
    }

    var text: String { pieces.map(\.text).joined() }

    mutating func add(_ text: String, _ style: Style = .plain) {
        pieces.append((text, style))
        width += text.count
    }

    /// Pads with spaces so the next piece starts at `column`.
    mutating func pad(to column: Int) {
        if column > width { add(String(repeating: " ", count: column - width)) }
    }

    /// Adds `text` ending at `column`, keeping at least one space after what's already there.
    mutating func trailing(_ text: String, _ style: Style = .plain, at column: Int) {
        guard width + 1 + text.count <= column else { return }
        pad(to: column - text.count)
        add(text, style)
    }

    func rendered(width limit: Int, colors: ColorMode) -> String {
        var output = "", used = 0
        for piece in pieces where used < limit {
            let text = used + piece.text.count > limit ? String(piece.text.prefix(limit - used)) : piece.text
            used += text.count
            let escape = piece.style.escape(colors)
            output += escape.isEmpty ? text : escape + text + "\u{1B}[0m"
        }
        return output
    }
}

/// Terminal drawing primitives: meters, sparklines and braille area charts.
enum TerminalChart {
    /// A horizontal meter in half-cell steps: the filled part and the empty track.
    static func meter(_ fraction: Double, width: Int) -> (filled: String, track: String) {
        let halves = Int((max(0, min(1, fraction)) * Double(width * 2)).rounded())
        let filled = String(repeating: "━", count: halves / 2) + (halves % 2 == 1 ? "╸" : "")
        return (filled, String(repeating: "━", count: width - (halves + 1) / 2))
    }

    /// One block per value (0...1), e.g. one per core.
    static func sparkline(_ values: [Double]) -> String {
        let blocks = Array("▁▂▃▄▅▆▇█")
        return String(values.map { blocks[max(0, min(7, Int(($0 * 7).rounded())))] })
    }

    /// An area chart `rows` tall in braille dots: two values per character, four dots per row.
    /// Values are 0...1; nil leaves a gap. Any value above zero shows at least one dot.
    static func area(_ values: [Double?], rows: Int) -> [String] {
        dots(values, rows: rows).map { String(String.UnicodeScalarView($0.map(character))) }
    }

    /// The dot pattern of each character in `area`, top row first, as braille bits.
    static func dots(_ values: [Double?], rows: Int) -> [[UInt32]] {
        let total = rows * 4
        let heights = values.map { value -> Int in
            guard let value, value.isFinite, value > 0 else { return 0 }
            return max(1, min(total, Int((value * Double(total)).rounded())))
        }
        // Dot bits from the bottom of a cell up, for its left and right column.
        let left: [UInt32] = [0x40, 0x04, 0x02, 0x01], right: [UInt32] = [0x80, 0x20, 0x10, 0x08]
        return (0..<rows).map { row in
            let base = (rows - 1 - row) * 4
            return stride(from: 0, to: heights.count, by: 2).map { pair in
                var bits: UInt32 = 0
                for i in 0..<max(0, min(4, heights[pair] - base)) { bits |= left[i] }
                if pair + 1 < heights.count {
                    for i in 0..<max(0, min(4, heights[pair + 1] - base)) { bits |= right[i] }
                }
                return bits
            }
        }
    }

    static func character(_ bits: UInt32) -> Unicode.Scalar {
        bits == 0 ? " " : Unicode.Scalar(0x2800 + bits)!
    }

    /// Spreads archive buckets (each `width` seconds) over `count` equal slices of `start...end`.
    /// A slice takes the highest value it overlaps, so short spikes survive; empty slices are gaps.
    static func columns(_ buckets: [Bucket], _ value: KeyPath<Bucket, Double> = \.average, width: Int,
                        from start: Date, to end: Date, count: Int) -> [Double?] {
        guard count > 0, end > start else { return [] }
        let origin = start.timeIntervalSince1970, step = end.timeIntervalSince(start) / Double(count)
        var result = [Double?](repeating: nil, count: count)
        for bucket in buckets {
            let from = (Double(bucket.start) - origin) / step, to = (Double(bucket.start + width) - origin) / step
            let first = max(0, Int(from.rounded(.down))), last = min(count - 1, Int(to.rounded(.up)) - 1)
            guard first <= last else { continue }
            for i in first...last { result[i] = max(result[i] ?? 0, bucket[keyPath: value]) }
        }
        return result
    }

    /// Spreads the live window (`capacity` samples once full, newest last) over `count` slices,
    /// keeping the newest at the right edge. Slices from before the first sample are gaps.
    static func columns(live values: [Double], capacity: Int, count: Int) -> [Double?] {
        guard count > 0, capacity > 0 else { return [] }
        let missing = capacity - values.count
        return (0..<count).map { i in
            let low = i * capacity / count, high = max(low + 1, (i + 1) * capacity / count)
            return (low..<high).compactMap { j in values.indices.contains(j - missing) ? values[j - missing] : nil }.max()
        }
    }
}

/// Raw-mode terminal on the alternate screen, restored on exit and around ^Z.
final class Terminal {
    private var original = termios()
    private var isRaw = false

    var size: (width: Int, height: Int) {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0, size.ws_row > 0 else { return (80, 24) }
        return (Int(size.ws_col), Int(size.ws_row))
    }

    func enter() {
        if tcgetattr(STDIN_FILENO, &original) == 0 {
            var raw = original
            raw.c_lflag &= ~tcflag_t(ECHO | ICANON)
            isRaw = tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0
        }
        write("\u{1B}[?1049h\u{1B}[?25l")
    }

    func leave() {
        write("\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l")
        if isRaw { tcsetattr(STDIN_FILENO, TCSAFLUSH, &original) }
        isRaw = false
    }

    /// Redraws in place (no clear, so no flicker), inside a synchronized update where supported.
    func draw(_ lines: [Line], colors: ColorMode) {
        let width = size.width
        // Stop one column short: a character in the last column leaves the cursor pending a wrap,
        // and erasing to the end of the line from there would wipe that character.
        let body = lines.map { $0.rendered(width: width - 1, colors: colors) + "\u{1B}[K" }.joined(separator: "\r\n")
        write("\u{1B}[?2026h\u{1B}[H" + body + "\u{1B}[J\u{1B}[?2026l")
    }

    func write(_ string: String) {
        var bytes = Array(string.utf8)[...]
        while !bytes.isEmpty {
            let written = bytes.withUnsafeBytes { Darwin.write(STDOUT_FILENO, $0.baseAddress, $0.count) }
            if written < 0 { if errno == EINTR { continue } else { return } }
            bytes = bytes.dropFirst(written)
        }
    }
}
