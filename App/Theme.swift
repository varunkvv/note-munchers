import SwiftUI

/// Colors. Near-black on warm off-white for the staff (less glare than pure white,
/// and light-on-dark smears more for astigmatic eyes). Kid screens stay in light mode.
enum Theme {
    static let paper = Color(red: 0.985, green: 0.962, blue: 0.918)
    static let ink = Color(red: 0.07, green: 0.07, blue: 0.09)
    /// increase contrast: plain black on a whiter paper
    static let paperHighContrast = Color(red: 1, green: 0.995, blue: 0.98)
    static let inkHighContrast = Color.black

    /// notes he already played in a group or line
    static let doneInk = Color(red: 0.6, green: 0.58, blue: 0.54)
    static let sparkle = Color(red: 1.0, green: 0.7, blue: 0.1)
    static let glow = Color(red: 1.0, green: 0.82, blue: 0.3)
    static let spaceTint = Color(red: 0.84, green: 0.91, blue: 1.0)

    static let keyLit = Color(red: 1.0, green: 0.58, blue: 0.12)
    static let keyWhite = Color.white
    static let keyBlack = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let keyEdge = Color(red: 0.35, green: 0.33, blue: 0.3)

    static let lane = Color(red: 0.95, green: 0.92, blue: 0.86)
    static let button = Color(red: 0.36, green: 0.72, blue: 0.45)
    static let parentIcon = Color(red: 0.55, green: 0.52, blue: 0.48)
}

/// Parent settings for the staff (vision). Stored in UserDefaults.
struct StaffStyle: Equatable {
    /// 0.6...1.0 of the biggest staff that fits the screen.
    var size = 1.0
    /// Staff, ledger line and stem weight as a fraction of the line gap.
    /// Engraving standard is ~0.13. Kept thick on purpose.
    var lineThickness = 0.14
    /// Faint tint in the four spaces so line vs space reads easier. Off by default.
    var spaceTint = false
    var highContrast = false

    var paper: Color { highContrast ? Theme.paperHighContrast : Theme.paper }
    var ink: Color { highContrast ? Theme.inkHighContrast : Theme.ink }

    enum Key {
        static let size = "staffSize"
        static let lineThickness = "lineThickness"
        static let spaceTint = "spaceTint"
    }

    static let sizeRange = 0.6...1.0
    static let thicknessRange = 0.08...0.24
}
