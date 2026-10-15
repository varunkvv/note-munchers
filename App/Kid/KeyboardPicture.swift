import NoteCore
import SwiftUI

/// A picture of piano keys with some lit up. On kid screens it's only a picture (not
/// tappable). The DEBUG on-screen keyboard reuses it with `onPress` / `onRelease`.
/// No letter names on the keys - middle C gets a small dot, like in his books.
struct KeyboardPicture: View {
    let range: ClosedRange<Pitch>
    var lit: [Pitch] = []
    var litColor = Theme.keyLit
    var onPress: ((Pitch) -> Void)?
    var onRelease: ((Pitch) -> Void)?

    @State private var held: Pitch?

    var body: some View {
        GeometryReader { proxy in
            let layout = KeyLayout(range: range, size: proxy.size)
            Canvas { context, _ in
                draw(&context, layout)
            }
            .frame(width: layout.width, height: layout.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(onPress == nil ? nil : press(layout, offset: proxy.size))
        }
    }

    private func press(_ layout: KeyLayout, offset size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = CGPoint(x: value.location.x - (size.width - layout.width) / 2,
                                    y: value.location.y - (size.height - layout.height) / 2)
                let key = layout.key(at: point)
                guard key != held else { return }
                if let held { onRelease?(held) }
                held = key
                if let key { onPress?(key) }
            }
            .onEnded { _ in
                if let held { onRelease?(held) }
                held = nil
            }
    }

    private func draw(_ context: inout GraphicsContext, _ layout: KeyLayout) {
        let litSet = Set(lit.map(\.midi))
        let edge = max(1.5, layout.whiteWidth * 0.05)
        for key in layout.whites {
            let rect = layout.rect(key).insetBy(dx: edge / 2, dy: edge / 2)
            let shape = Path(roundedRect: rect, cornerRadius: layout.whiteWidth * 0.12)
            let isLit = litSet.contains(key.midi) || key == held
            context.fill(shape, with: .color(isLit ? litColor : Theme.keyWhite))
            context.stroke(shape, with: .color(Theme.keyEdge), lineWidth: edge)
            if key == .middleC {
                let d = layout.whiteWidth * 0.26
                let dot = CGRect(x: rect.midX - d / 2, y: rect.maxY - d * 2.2, width: d, height: d)
                context.fill(Path(ellipseIn: dot), with: .color(isLit ? Theme.ink.opacity(0.55) : Theme.keyEdge.opacity(0.7)))
            }
        }
        for key in layout.blacks {
            let rect = layout.rect(key)
            let shape = Path(roundedRect: rect, cornerRadius: layout.whiteWidth * 0.08)
            let isLit = litSet.contains(key.midi) || key == held
            context.fill(shape, with: .color(isLit ? litColor : Theme.keyBlack))
        }
    }
}

/// Key rectangles for a range. White keys share the width, black keys sit on top.
struct KeyLayout {
    let whites: [Pitch]
    let blacks: [Pitch]
    let whiteWidth: CGFloat
    let width: CGFloat
    let height: CGFloat
    private let whiteIndex: [Int: Int]

    init(range: ClosedRange<Pitch>, size: CGSize) {
        let all = (range.lowerBound.midi...range.upperBound.midi).map(Pitch.init(midi:))
        whites = all.filter(\.isWhiteKey)
        blacks = all.filter { !$0.isWhiteKey }
        var index: [Int: Int] = [:]
        for (i, key) in whites.enumerated() { index[key.midi] = i }
        whiteIndex = index
        // real keys are about 1 : 4.5. keep the picture that shape and fit it
        let byWidth = size.width / CGFloat(max(1, whites.count))
        let byHeight = size.height / 4.2
        whiteWidth = max(4, min(byWidth, byHeight))
        width = whiteWidth * CGFloat(whites.count)
        height = whiteWidth * 4.2
    }

    func rect(_ key: Pitch) -> CGRect {
        if let i = whiteIndex[key.midi] {
            return CGRect(x: CGFloat(i) * whiteWidth, y: 0, width: whiteWidth, height: height)
        }
        // a black key sits on the line after the white key below it
        let below = whiteIndex[key.midi - 1] ?? 0
        let w = whiteWidth * 0.6
        return CGRect(x: CGFloat(below + 1) * whiteWidth - w / 2, y: 0, width: w, height: height * 0.62)
    }

    func key(at point: CGPoint) -> Pitch? {
        if let black = blacks.first(where: { rect($0).contains(point) }) { return black }
        return whites.first { rect($0).contains(point) }
    }
}
