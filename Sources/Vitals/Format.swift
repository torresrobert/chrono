import Foundation

enum Format {
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func bytes(_ value: some BinaryInteger) -> String {
        bytes(Double(value))
    }

    /// Binary units (like Activity Monitor's memory column): 1.2 GB, 512 MB.
    static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var v = max(0, value)
        var i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        let digits = i == 0 ? 0 : (v < 10 ? 1 : 0)
        return String(format: "%.\(digits)f %@", v, units[i])
    }

    /// Decimal units, matching how Finder reports disk capacity.
    static func diskBytes(_ value: some BinaryInteger) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var v = max(0, Double(value))
        var i = 0
        while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
        let digits = i == 0 ? 0 : (v < 10 ? 1 : 0)
        return String(format: "%.\(digits)f %@", v, units[i])
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        bytes(bytesPerSecond) + "/s"
    }

    /// Compact rate for the menu bar: always ≤ 7 characters, e.g. "12 KB/s", "1.4 MB/s".
    static func shortRate(_ bytesPerSecond: Double) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var v = max(0, bytesPerSecond)
        var i = 0
        while v >= 1000, i < units.count - 1 { v /= 1024; i += 1 }
        let number = (i > 0 && v < 10) ? String(format: "%.1f", v) : String(format: "%.0f", v)
        return "\(number) \(units[i])B/s"
    }

    @MainActor
    static func temperature(_ celsius: Double, decimals: Bool = false) -> String {
        let value = Settings.shared.fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return decimals ? String(format: "%.1f°", value) : "\(Int(value.rounded()))°"
    }

    static func rpm(_ value: Double) -> String {
        "\(Int(value.rounded()).formatted()) rpm"
    }

    static func watts(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f W", value) : "\(Int(value.rounded())) W"
    }

    static func duration(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        let days = seconds / 86400, hours = (seconds % 86400) / 3600, minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func minutes(_ total: Int) -> String {
        "\(total / 60):" + String(format: "%02d", total % 60)
    }
}
