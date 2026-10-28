import SwiftUI

/// The demo's palette, the same hex values the Android demo uses.
///
/// The violet accents are the Funnelbase dashboard's own brand ramp, so the demo app and the
/// analytics UI read as one product rather than as two unrelated screenshots — and so the demos
/// read as one product too.
///
/// Green and red are reserved strictly for price direction and are never the only signal — every
/// place they appear, a ▲/▼ glyph appears with them. Roughly one man in twelve cannot separate
/// the two, and "is my portfolio up" is not a question to answer with hue alone.
enum TradeDemoColors {
    static let accent = Color(hex: 0x8B5CF6)
    static let accentMuted = Color(hex: 0x6D3FD6)
    static let onAccent = Color(hex: 0xFFFFFF)

    static let background = Color(hex: 0x0B0B10)
    static let surface = Color(hex: 0x15151E)
    static let surfaceElevated = Color(hex: 0x1D1D28)
    static let outline = Color(hex: 0x2E2E3D)

    static let textPrimary = Color(hex: 0xF2F2F7)
    static let textSecondary = Color(hex: 0x9E9EB3)

    static let up = Color(hex: 0x3DDC97)
    static let down = Color(hex: 0xFF6B6B)

    static let pending = Color(hex: 0xF5C451)
    static let filled = up
    static let cancelled = Color(hex: 0x7C7C93)
}

extension Color {
    /// Written as `0xRRGGBB`, so the palette above can be read against the Kotlin one line for
    /// line rather than translated into three fractions each.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
