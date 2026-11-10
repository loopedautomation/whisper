import SwiftUI

extension Color {
    init(hex: UInt) {
        self = Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

/// The Looped brand's state colours for the menu bar icon, in the brand's Day
/// and Night values. Each is a fill with the glyph colour that goes on it,
/// and the glyph is always white, so every fill is a deep one.
enum BrandColor {
    struct Pill {
        let fill: Color
        let glyph: Color
    }

    private static let white = Color.white

    /// Orange: the microphone is on. Not a brand colour, on purpose: it is
    /// the orange macOS itself shows while the microphone is in use, so the
    /// two indicators read as the same thing. The same in Day and Night.
    static func recording(dark: Bool) -> Pill {
        Pill(fill: Color(hex: 0xED9B00), glyph: white)
    }

    /// Moss green: an AI model is rewriting text. The deep Day value in both
    /// modes, for the white glyph.
    static func rewriting(dark: Bool) -> Pill {
        Pill(fill: Color(hex: 0x4B7A3F), glyph: white)
    }

    /// Violet (accent-fill): transcribing, or loading a model.
    static func working(dark: Bool) -> Pill {
        Pill(fill: Color(hex: dark ? 0x7358D6 : 0x6554C0), glyph: white)
    }

    /// Oxblood: something went wrong. The deep Day value in both modes; the
    /// lighter Night oxblood can't carry a white glyph.
    static func error(dark: Bool) -> Pill {
        Pill(fill: Color(hex: 0xA8322C), glyph: white)
    }
}
