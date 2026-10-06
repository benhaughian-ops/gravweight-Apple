import SwiftUI

extension Color {
    /// `Color(hex: 0xFF9800)`
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Parses "#3b82f6" / "3b82f6". Returns nil when invalid.
    init?(hexString: String?) {
        guard var s = hexString?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

/// Fixed brand colours — identical hex values to the Android `Color.kt` files.
enum Brand {
    static let cyanGlow = Color(hex: 0xFF9800)      // primary orange
    static let electricBlue = Color(hex: 0xF57C00)  // secondary orange
    static let deepOrange = Color(hex: 0xE53935)    // red / destructive
    static let spaceBlack = Color(hex: 0x212121)
    static let whiteText = Color(hex: 0xE8F4F8)
    static let dimText = Color(hex: 0x9E9E9E)
    static let plateGray = Color(hex: 0x8A8A9A)
    static let glass = Color.white.opacity(0.10)

    static let myPostAccent = Color(hex: 0x3B82F6)

    // Home dashboard
    static let stepGreen = Color(hex: 0x34D399)
    static let kcalOrange = Color(hex: 0xFF8A1F)
    static let minuteBlue = Color(hex: 0x38BDF8)
    static let heartRed = Color(hex: 0xF43F5E)

    // Social
    static let likeRed = Color(hex: 0xEF4444)
    static let purple = Color(hex: 0xA855F7)
    static let success = Color(hex: 0x22C55E)
}
