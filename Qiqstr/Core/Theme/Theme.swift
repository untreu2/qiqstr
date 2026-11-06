import SwiftUI
import UIKit

enum AppColors {
    static let accent = Color(light: Color(red: 210/255, green: 100/255, blue: 0), dark: Color(red: 240/255, green: 160/255, blue: 90/255))
    static let background = Color(light: .white, dark: Color(red: 10/255, green: 10/255, blue: 10/255))
    static let surface = Color(light: .white, dark: Color(red: 15/255, green: 15/255, blue: 15/255))
    static let textPrimary = Color(light: .black, dark: .white)
    static let textSecondary = Color(light: Color.black.opacity(0.54), dark: Color(white: 0.878))
    static let error = Color(light: Color(red: 1, green: 0.32, blue: 0.32), dark: Color(hex: 0xFF6B6B))
    static let success = Color(hex: 0x2E9E4F)
    static let warning = Color(light: Color(hex: 0xFFC107), dark: Color(hex: 0xFFA726))
    static let border = Color(light: Color.black.opacity(0.12), dark: Color(hex: 0x333333))
    static let divider = Color(light: Color.black.opacity(0.12), dark: Color(hex: 0x2A2A2A))
    static let overlayLight = Color(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.1))
    static let inputFill = Color(light: Color.black.opacity(0.06), dark: Color(hex: 0x141414))
    static let avatarPlaceholder = Color(light: Color.black.opacity(0.26), dark: Color(hex: 0x666666))
    static let reaction = Color(hex: 0xFF6B6B)
    static let reply = Color(hex: 0x74C0FC)
    static let repost = Color(hex: 0x2E9E4F)
    static let zap = Color(hex: 0xECB200)
    static let switchActive = Color(hex: 0x2E9E4F)
    static let link = Color(uiColor: .link)
    static let tile = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.08))
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

enum AppFont {
    static func brand(_ size: CGFloat) -> Font { .custom("Poppins-Bold", size: size) }
    static func brandSemibold(_ size: CGFloat) -> Font { .custom("Poppins-SemiBold", size: size) }
}

enum ThemePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
