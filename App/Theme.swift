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

    /// Words on kid screens: a warm dark brown, softer than the staff's ink.
    static let kidText = Color(red: 0.27, green: 0.2, blue: 0.16)
    /// The one line under a heading.
    static let kidTextSoft = Color(red: 0.45, green: 0.38, blue: 0.32)
    /// "All done" and the parts that go with it.
    static let homeButton = Color(red: 0.38, green: 0.62, blue: 0.95)

    /// Kid screen words: SF Rounded, big and bold. A few plain words a first grader
    /// reads on his own, never a paragraph, never a judging word.
    static func kidFont(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Parent settings for the staff (vision). Stored in UserDefaults.
struct StaffStyle: Equatable {
    /// Line gap as a multiple of `Metrics.gap` (30pt on the iPad). The same for every lesson.
    var size = 1.0
    /// Staff, ledger line and stem weight as a fraction of the line gap.
    /// Engraving is ~0.11-0.13. A little heavier on purpose.
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

    static let sizeRange = 0.8...1.3
    static let thicknessRange = 0.08...0.24

    /// Settings saved by an older build can be outside today's ranges.
    var clamped: StaffStyle {
        var style = self
        style.size = min(max(size, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        style.lineThickness = min(max(lineThickness, Self.thicknessRange.lowerBound), Self.thicknessRange.upperBound)
        return style
    }
}
