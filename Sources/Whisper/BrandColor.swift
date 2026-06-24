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

/// Shared brand + status colors used throughout the app (menu bar, HUD, etc.).
enum BrandColor {
    static let primary      = Color(hex: 0x685EF6)   // app accent
    static let recording    = Color(hex: 0xED9B00)
    static let transcribing = Color(hex: 0x685EF6)   // also loading / rewriting
    static let error        = Color(hex: 0xD02E1F)
    static let success      = Color(hex: 0x37946A)
}

extension AppStatus {
    /// Tint color for the current state, or nil when idle.
    var tint: Color? {
        switch self {
        case .recording:                                return BrandColor.recording
        case .transcribing, .rewriting, .loadingModel:  return BrandColor.transcribing
        case .error:                                    return BrandColor.error
        case .idle:                                     return nil
        }
    }
}
