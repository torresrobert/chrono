import AppKit
import SwiftUI

// Chrono's adoption of torres-style (the Torres Labs design spec, THEME.md): shared neutrals,
// semantic status colors, a per-app accent, radius scale, branded gradient and motion curve.
//
// The accent is chrome only (icon, header gradient, controls, the gauge redline) — never data.
// In a monitor red reads as "something's wrong", and that job belongs to `Theme.negative`.

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: alpha)
    }

    /// A color that resolves per appearance, like an asset-catalog colorset.
    init(light: UInt, dark: UInt, alpha: Double = 1.0) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
        })
    }
}

enum Accent: String, CaseIterable, Identifiable {
    case racingRed, forecastlyBlue, fescueGreen, techsheetTeal, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .racingRed: "Racing Red"
        case .forecastlyBlue: "Blue"
        case .fescueGreen: "Green"
        case .techsheetTeal: "Teal"
        case .graphite: "Graphite"
        }
    }

    var color: Color {
        switch self {
        case .racingRed: Color(light: 0xC8102E, dark: 0xF0475A)
        case .forecastlyBlue: Color(light: 0x274BB2, dark: 0x6D8CFF)
        case .fescueGreen: Color(light: 0x357A56, dark: 0x55B685)
        case .techsheetTeal: Color(light: 0x0C7B7F, dark: 0x3EBFC4)
        case .graphite: Color(light: 0x374151, dark: 0x9CA3AF)
        }
    }
}

enum Theme {
    // Shared neutrals
    static let background = Color(light: 0xF5F5F7, dark: 0x0F121A)
    static let surface = Color(light: 0xFFFFFF, dark: 0x141824)
    static let border = Color(light: 0xE5E7EB, dark: 0x1F2533)
    static let textPrimary = Color(light: 0x0B0C0F, dark: 0xF3F4F6)
    static let textSecondary = Color(light: 0x0B0C0F, dark: 0xF3F4F6, alpha: 0.62)

    // Semantic status
    static let positive = Color(hex: 0x16A34A)
    static let warning = Color(hex: 0xF59E0B)
    static let negative = Color(hex: 0xDC2626)

    @MainActor static var accent: Color { Settings.shared.accent.color }

    // Radius scale
    static let radiusSmall: CGFloat = 8
    static let radius: CGFloat = 10
    static let radiusCard: CGFloat = 16

    /// torres-style ease-out: cubic-bezier(0.16, 1, 0.3, 1).
    static func ease(_ duration: Double = 0.18) -> Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: duration)
    }

    static func load(_ fraction: Double) -> Color {
        fraction < 0.6 ? positive : fraction < 0.85 ? warning : negative
    }

    static func temperature(_ celsius: Double) -> Color {
        celsius < 75 ? positive : celsius < 90 ? warning : negative
    }
}

/// Data series colors: chosen to sit apart from both the accent and the status colors.
enum Series {
    static let primary = Color(light: 0x2563EB, dark: 0x60A5FA)    // blue
    static let secondary = Color(light: 0x7C3AED, dark: 0xA78BFA)  // violet
    static let tertiary = Color(light: 0x0891B2, dark: 0x22D3EE)   // cyan
    static let neutral = Color(light: 0x9CA3AF, dark: 0x4B5563)
    static let heat = Color(light: 0xEA580C, dark: 0xFB923C)
    static let power = Color(light: 0xCA8A04, dark: 0xFACC15)
}

/// torres-style BrandedGradientBackground: the accent at low opacity, fading out downward.
struct BrandedGradientBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color

    var body: some View {
        let opacity = colorScheme == .dark ? 0.15 : 0.10
        Group {
            if #available(macOS 15, *) {
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                        [0.0, 0.4], [0.5, 0.35], [1.0, 0.4],
                        [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
                    ],
                    colors: [
                        tint.opacity(opacity), tint.opacity(opacity * 1.2), tint.opacity(opacity),
                        tint.opacity(opacity * 0.4), tint.opacity(opacity * 0.3), tint.opacity(opacity * 0.4),
                        .clear, .clear, .clear,
                    ]
                )
            } else {
                LinearGradient(colors: [tint.opacity(opacity), tint.opacity(opacity * 0.3), .clear],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Card surface. The popover is already glass on macOS 26, and Apple's guidance is not to stack
    /// glass on glass, so cards use the surface token at partial opacity plus a hairline border.
    func appCard(cornerRadius: CGFloat = Theme.radius, padding: CGFloat = 10) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Theme.surface.opacity(0.42)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}
