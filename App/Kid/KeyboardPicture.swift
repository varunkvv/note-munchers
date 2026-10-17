import NoteCore
import SwiftUI

/// A picture of piano keys with some lit up. On kid screens it's only a picture (not
/// tappable). The DEBUG on-screen keyboard reuses it with `onPress` / `onRelease`.
/// No letter names on the keys - middle C gets a small dot, like in his books - except
/// on a new note's intro, where a big letter sits on the lit key (`letters`): that's how
/// he learns its name now that the voice doesn't say it. The keys are too thin for a
/// letter a 6 year old reads easily, so it's a badge standing on the key's top edge.
struct KeyboardPicture: View {
    let range: ClosedRange<Pitch>
    var lit: [Pitch] = []
    var litColor = Theme.keyLit
    /// Show the letter of each lit key, big. Intro screens only.
    var letters = false
    /// Finger numbers on lit keys (the hint picture), from NoteCore.
    var fingers: [FingerMark] = []
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
            .overlay(alignment: .topLeading) {
                if letters {
                    ForEach(lit, id: \.midi) { key in
                        if let name = NoteName(key) {
                            let size = min(76, max(54, layout.whiteWidth * 2.4))
                            KeyLetter(name: name, size: size)
                                .position(x: layout.rect(key).midX, y: -size * 0.62 + layout.whiteWidth * 0.3)
                        }
                    }
                }
            }
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
        // the finger on a lit key, low on the key where his finger lands (above middle C's dot)
        for mark in fingers where litSet.contains(mark.pitch.midi) {
            let rect = layout.rect(mark.pitch)
            let white = mark.pitch.isWhiteKey
            let size = white ? min(layout.whiteWidth * 0.95, 34) : min(layout.whiteWidth * 0.62, 22)
            let y = rect.maxY - (white ? layout.whiteWidth * 1.35 : size * 0.85)
            let text = Text("\(mark.finger)").font(Theme.kidFont(size, weight: .heavy))
                .foregroundColor(Theme.ink.opacity(0.35 + 0.65 * mark.strength))
            context.draw(text, at: CGPoint(x: rect.midX, y: y), anchor: .center)
        }
    }
}

/// A new note's letter: a round badge in the lit key's colour with a point that stands
/// on the key, the letter big and dark.
struct KeyLetter: View {
    let name: NoteName
    let size: CGFloat

    var body: some View {
        VStack(spacing: -size * 0.08) {
            ZStack {
                Circle().fill(Theme.keyWhite)
                Circle().strokeBorder(Theme.keyLit, lineWidth: size * 0.09)
                Text(name == .fSharp ? "F♯" : name.rawValue)
                    .font(Theme.kidFont(size * (name == .fSharp ? 0.46 : 0.6), weight: .heavy))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: size, height: size)
            Triangle()
                .fill(Theme.keyLit)
                .frame(width: size * 0.34, height: size * 0.24)
        }
        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
        .accessibilityHidden(true)
    }
}

/// Pointing down.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
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
