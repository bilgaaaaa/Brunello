import SwiftUI

/// Colors and shapes shared by every screen: a soft "gelato" palette that follows light and dark mode.
enum Theme {
    static let background = Color(light: 0xF8F6FD, dark: 0x1A1631)
    static let card = Color(light: 0xFFFFFF, dark: 0x251F40)
    static let ink = Color(light: 0x2A2342, dark: 0xF1EEFA)
    static let inkSoft = Color(light: 0x675F84, dark: 0xABA4C6)
    static let line = Color(light: 0xE6E0F3, dark: 0x352E57)
    static let brand = Color(light: 0xD6336C, dark: 0xFF7AA2)
    static let onBrand = Color(light: 0xFFFFFF, dark: 0x3A0A1F)

    static let cornerRadius: CGFloat = 20
    static let screenPadding: CGFloat = 16
}

extension Color {
    /// A color written as two hex values, one for light mode and one for dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension EntryKind {
    /// Each kind has its own flavor so the diary can be read at a glance.
    var color: Color {
        switch self {
        case .food: Color(light: 0xFF9A3D, dark: 0xFFA857)
        case .poo: Color(light: 0xA8714B, dark: 0xC08B66)
        case .pee: Color(light: 0xEDB91F, dark: 0xF2C744)
        case .walk, .play: Color(light: 0x4FB67C, dark: 0x63C690)
        case .health: Color(light: 0x2FAFC0, dark: 0x4CC3D2)
        case .photo: Color(light: 0x7A69F0, dark: 0x9486F5)
        }
    }

    /// Soft background used behind the kind's emoji and buttons.
    var tint: Color {
        color.opacity(0.22)
    }
}
