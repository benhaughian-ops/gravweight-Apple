import SwiftUI
import UIKit

// MARK: - Theme palette (dark / light, same values as Android Theme.kt)

struct Palette {
    let bg: Color        // SpaceBlack
    let glass: Color     // GlassSurface
    let text: Color      // WhiteText
    let dim: Color       // DimText
    let plate: Color     // PlateGray
    let session: Color   // SessionSurface
    let menu: Color      // MenuSurface
    let myPostTint: Color

    static let dark = Palette(
        bg: Color(hex: 0x212121), glass: Color.white.opacity(0.10), text: Color(hex: 0xE8F4F8),
        dim: Color(hex: 0x9E9E9E), plate: Color(hex: 0x8A8A9A), session: Color(hex: 0x1B2230),
        menu: Color(hex: 0x2C2C2C), myPostTint: Color(hex: 0x3B82F6).opacity(0.14)
    )

    static let light = Palette(
        bg: Color(hex: 0xF5F6FA), glass: Color.black.opacity(0.04), text: Color(hex: 0x1E293B),
        dim: Color(hex: 0x64748B), plate: Color(hex: 0xCBD5E1), session: Color(hex: 0xE6ECF5),
        menu: Color.white, myPostTint: Color(hex: 0x3B82F6).opacity(0.14)
    )
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.dark
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Formatting helpers

enum Fmt {
    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    /// 12,345
    static func thousands(_ v: Int) -> String { grouped.string(from: NSNumber(value: v)) ?? "\(v)" }
    static func thousands(_ v: Double) -> String { grouped.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))" }

    /// "135" or "137.5"
    static func trim(_ v: Double) -> String {
        if v >= 1000 { return thousands(v) }
        return v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// Weight for display in the user's unit (logs are always stored in lbs).
    static func weight(_ lbs: Double, metric: Bool) -> String {
        metric ? String(format: "%.1f kg", lbs * 0.453592) : "\(Int(lbs)) lbs"
    }

    static func date(_ d: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.dateFormat = pattern
        return f.string(from: d)
    }

    static func ago(_ d: Date?) -> String {
        guard let d else { return "not synced yet" }
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }

    /// Server timestamps → "2026-10-04 21:17" (Android shows the first 16 chars).
    static func serverDate(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return String(s.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}

// MARK: - Reusable views

/// Rounded glass card (Android `Card` helper on Home: 22dp radius, 18dp padding).
struct GlassCard<Content: View>: View {
    @Environment(\.palette) private var p
    var radius: CGFloat = 22
    var padding: CGFloat = 18
    var border: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.glass, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                if let border { RoundedRectangle(cornerRadius: radius).stroke(border, lineWidth: 1) }
            }
    }
}

/// "THIS WEEK" style label.
struct SectionLabel: View {
    @Environment(\.palette) private var p
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .tracking(1)
            .foregroundStyle(p.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
    }
}

/// Header title used on each tab ("WORKOUT LOG", "SOCIAL", …).
struct ScreenTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .heavy))
            .tracking(3)
            .foregroundStyle(Brand.cyanGlow)
    }
}

/// 1W / 1M / All Time chips.
struct RangeChips: View {
    @Environment(\.palette) private var p
    let ranges: [String]
    @Binding var selected: String
    var unselectedBackground: Color? = nil

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ranges, id: \.self) { r in
                let on = r == selected
                Button { selected = r } label: {
                    Text(r)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(on ? Brand.cyanGlow : p.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(on ? Brand.cyanGlow.opacity(0.2) : (unselectedBackground ?? p.glass), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Brand.cyanGlow : p.dim.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Circular avatar: profile picture from a `data:image/...;base64,` URL, else the initial on red.
struct UserAvatar: View {
    let avatarUrl: String?
    let name: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Brand.deepOrange)
            if let img = Self.decode(avatarUrl) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private static var cache = NSCache<NSString, UIImage>()

    static func decode(_ dataUrl: String?) -> UIImage? {
        guard let dataUrl, !dataUrl.isEmpty else { return nil }
        if let hit = cache.object(forKey: dataUrl as NSString) { return hit }
        let b64: Substring
        if let r = dataUrl.range(of: "base64,") { b64 = dataUrl[r.upperBound...] } else { b64 = Substring(dataUrl) }
        guard let data = Data(base64Encoded: String(b64), options: .ignoreUnknownCharacters), let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: dataUrl as NSString)
        return img
    }

    /// Centre-crops to a square, scales to 256px and returns a JPEG data URL (same as Android).
    static func dataUrl(from image: UIImage, sizePx: CGFloat = 256) -> String? {
        let side = min(image.size.width, image.size.height)
        let cropRect = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: sizePx, height: sizePx), format: format)
        let scaled = renderer.image { _ in
            let scale = sizePx / side
            image.draw(in: CGRect(x: -cropRect.minX * scale, y: -cropRect.minY * scale, width: image.size.width * scale, height: image.size.height * scale))
        }
        guard let jpeg = scaled.jpegData(compressionQuality: 0.82) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}

/// Android-style toast pinned near the bottom.
struct ToastOverlay: View {
    let message: String?
    var body: some View {
        VStack {
            Spacer()
            if let message {
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: message)
    }
}

/// Outlined text field matching the Android OutlinedTextField look.
struct OutlinedField: View {
    @Environment(\.palette) private var p
    let placeholder: String
    @Binding var text: String
    var accent: Color = Brand.cyanGlow
    var keyboard: UIKeyboardType = .default
    var axis: Axis = .horizontal

    var body: some View {
        TextField(placeholder, text: $text, axis: axis)
            .keyboardType(keyboard)
            .font(.system(size: 14))
            .foregroundStyle(p.text)
            .tint(accent)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).stroke(p.dim.opacity(0.5), lineWidth: 1))
    }
}

/// Simple hit-testable flow-row of chips.
struct ChipButton: View {
    @Environment(\.palette) private var p
    let text: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? p.bg : p.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Brand.cyanGlow : p.glass, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
