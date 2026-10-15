import CoreGraphics
import CoreText
import Foundation
import SwiftUI

/// Clef glyphs from the Bravura SMuFL font (SIL OFL, license next to the font file).
///
/// The font is loaded straight from the bundle with CGFont, so it works the same on
/// iOS and macOS without registering it. Only the clefs come from the font - every
/// other mark is drawn as a path so line weights stay under our control.
enum Bravura {
    enum Glyph: UInt16 {
        case gClef = 0xE050
        case fClef = 0xE062
    }

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
        guard let font else { return nil }
        var char = glyph.rawValue
        var cgGlyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font, &char, &cgGlyph, 1), cgGlyph != 0 else { return nil }
        // font is at 100pt, em = 4 staff spaces
        let scale = staffSpace * 4 / 100
        var transform = CGAffineTransform(scaleX: scale, y: -scale)
        guard let cgPath = CTFontCreatePathForGlyph(font, cgGlyph, &transform) else { return nil }
        return Path(cgPath)
    }
}
