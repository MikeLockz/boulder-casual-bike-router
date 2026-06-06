import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    static let forestDeep = Color(hex: "#0A1F1F")
    static let surfaceDim = Color(hex: "#121414")
    static let surfaceElevated = Color(hex: "#1C2121")
    static let surfaceContainer = Color(hex: "#1E2020")
    static let onSurface = Color(hex: "#E2E2E2")
    static let onSurfaceVariant = Color(hex: "#BBCAC4")
    static let mintGlow = Color(hex: "#26FFD4")
    static let primaryMint = Color(hex: "#59DBBF")
    static let primaryContainer = Color(hex: "#00A98F")
    static let successTeal = Color(hex: "#00CCAA")
    static let errorRose = Color(hex: "#FF5C5C")
    static let errorContainer = Color(hex: "#93000A")
    static let onErrorContainer = Color(hex: "#FFDAD6")
}
