import CoreGraphics
import CoreText
import Foundation
import SwiftUI

/// Clef, sharp, brace, time signature, rest and dot glyphs from the Bravura SMuFL font
/// (SIL OFL, license next to the font file).
///
/// The font is loaded straight from the bundle with CGFont, so it works the same on
/// iOS and macOS without registering it. Clefs, the key signature's sharp, the grand
/// staff's brace, time signature digits, rests and the augmentation dot come from the
/// font - heads, stems, beams and lines are drawn as paths so their weights stay under
/// our control.
enum Bravura {
    enum Glyph: UInt16 {
        case gClef = 0xE050
        case fClef = 0xE062
        /// accidentalSharp. Origin on the line or space it marks.
        case sharp = 0xE262
        /// brace, one staff tall and 0.28 spaces wide. Origin at its bottom left,
        /// stretched to the height of the grand staff.
        case brace = 0xE000
        /// timeSig0. Add the digit for 1-9. Two spaces tall, centred on its origin's y
        case timeSig0 = 0xE080
        /// restWhole: hangs from its origin, which goes on the second line from the top
        case restWhole = 0xE4E3
        /// restHalf: sits on its origin, which goes on the middle line
        case restHalf = 0xE4E4
        /// restQuarter: centred on its origin, on the middle line
        case restQuarter = 0xE4E5
        /// augmentationDot: centred on its origin
        case dot = 0xE1E7
    }

    /// The time signature digit glyph for 0-9.
    static func digit(_ n: Int) -> UInt16 { Glyph.timeSig0.rawValue + UInt16(max(0, min(9, n))) }

    private static let font: CTFont? = {
        guard let url = Bundle.main.url(forResource: "Bravura", withExtension: "otf"),
              let provider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(provider)
        else { return nil }
        return CTFontCreateWithGraphicsFont(cgFont, 100, nil, nil)
    }()

    static var isAvailable: Bool { font != nil }

    /// The glyph as a y-down path with its SMuFL origin at (0, 0). In SMuFL the em is
    /// one staff height, so `staffSpace` (the line gap) sets the size. The G clef's
    /// origin sits on the G line, the F clef's on the F line.
    static func path(_ glyph: Glyph, staffSpace: CGFloat) -> Path? {
        path(code: glyph.rawValue, staffSpace: staffSpace)
    }

    static func path(code: UInt16, staffSpace: CGFloat) -> Path? {
        guard let font else { return nil }
        var char = code
        var cgGlyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font, &char, &cgGlyph, 1), cgGlyph != 0 else { return nil }
        // font is at 100pt, em = 4 staff spaces
        let scale = staffSpace * 4 / 100
        var transform = CGAffineTransform(scaleX: scale, y: -scale)
        guard let cgPath = CTFontCreatePathForGlyph(font, cgGlyph, &transform) else { return nil }
        return Path(cgPath)
    }
}
