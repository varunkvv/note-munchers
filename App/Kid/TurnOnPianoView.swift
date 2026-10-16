import NoteCore
import SwiftUI

/// "Turn on the piano": a picture of a piano, its cable slowly plugging in and then its
/// power button lighting up, with the words under it. Shown until a MIDI source shows
/// up, before a session and whenever the piano drops mid-session. A USB-MIDI cable
/// shows up as a source even with the piano off, so it's really about the cable.
///
/// One thing moves at a time, on a 6.4s loop: the plug slides in, then the button
/// glows, then the cable fades away and back out. With reduce motion it's one still
/// picture, plugged in and lit.
struct TurnOnPianoView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var start = Date()

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let width = min(proxy.size.width * 0.55, s * 0.95)
            ZStack {
                Theme.paper.ignoresSafeArea()
                VStack(spacing: s * 0.07) {
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
                        PianoPicture(
                            width: width,
                            state: reduceMotion ? .pluggedIn : .at(timeline.date.timeIntervalSince(start))
                        )
                    }
                    Text("Turn on the piano")
                        .font(Theme.kidFont(s * 0.075, weight: .heavy))
                        .foregroundStyle(Theme.kidText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { start = Date() }
    }
}

/// A digital piano from the front: a dark body, a top panel with a round power button,
/// the keys, and a cable that plugs into its right side.
private struct PianoPicture: View {
    let width: CGFloat
    let state: Phase

    struct Phase {
        /// 0 plug out ... 1 in the socket
        var plug: Double
        /// 0 off ... 1 the power button lit
        var power: Double
        /// the cable's opacity
        var cable: Double

        static let pluggedIn = Phase(plug: 1, power: 1, cable: 1)
        static let cycle = 6.4

        /// plug in (0.5-1.7s), light up (2.2-3.0s), hold, then the light and the cable
        /// fade (4.8-5.4s) and the cable fades back in, out of the socket (5.6-6.2s)
        static func at(_ t: Double) -> Phase {
            let x = t.truncatingRemainder(dividingBy: cycle)
            func ease(_ a: Double, _ b: Double) -> Double {
                let u = min(1, max(0, (x - a) / (b - a)))
                return u * u * (3 - 2 * u)
            }
            let fadeOut = ease(4.8, 5.4)
            return Phase(
                plug: x < 5.5 ? ease(0.5, 1.7) : 0,
                power: ease(2.2, 3.0) * (1 - fadeOut),
                cable: x < 5.5 ? 1 - fadeOut : ease(5.6, 6.2)
            )
        }
    }

    var body: some View {
        let w = width
        let h = w * 0.36
        // room for the cable on the right, the same on the left so the piano stays centred
        let side = w * 0.2
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                draw(&context, body: CGRect(x: side, y: 0, width: w, height: h))
            } symbols: {
                Image(systemName: "power")
                    .font(.system(size: h * 0.09, weight: .heavy))
                    .foregroundStyle(.white)
                    .tag("power")
            }
            KeyboardPicture(range: Pitch("C3")!...Pitch("C5")!)
                .frame(width: w * 0.92, height: h * 0.62)
                .offset(x: side + w * 0.04, y: h * 0.32)
        }
        .frame(width: w + 2 * side, height: h * 1.3)
    }

    private func draw(_ context: inout GraphicsContext, body: CGRect) {
        let h = body.height
        let w = body.width
        context.fill(Path(roundedRect: body, cornerRadius: h * 0.08), with: .color(Color(red: 0.25, green: 0.22, blue: 0.23)))
        // the keys sit in a slightly darker well
        let well = CGRect(x: body.minX + w * 0.03, y: body.minY + h * 0.29, width: w * 0.94, height: h * 0.67)
        context.fill(Path(roundedRect: well, cornerRadius: h * 0.03), with: .color(Color(red: 0.16, green: 0.14, blue: 0.15)))

        // power button on the panel, left
        let r = h * 0.085
        let button = CGPoint(x: body.minX + w * 0.07, y: body.minY + h * 0.145)
        if state.power > 0 {
            let halo = r * (1.5 + 0.5 * state.power)
            context.fill(Path(ellipseIn: CGRect(x: button.x - halo, y: button.y - halo, width: halo * 2, height: halo * 2)),
                         with: .color(Theme.button.opacity(0.35 * state.power)))
        }
        let off = Color(red: 0.5, green: 0.48, blue: 0.48)
        context.fill(Path(ellipseIn: CGRect(x: button.x - r, y: button.y - r, width: r * 2, height: r * 2)),
                     with: .color(off.mix(with: Theme.button, by: state.power)))
        if let symbol = context.resolveSymbol(id: "power") {
            context.draw(symbol, at: button)
        }
        // two little speaker grilles on the right of the panel
        for i in 0..<2 {
            let grille = CGRect(x: body.minX + w * (0.72 + 0.1 * CGFloat(i)), y: body.minY + h * 0.1, width: w * 0.08, height: h * 0.09)
            context.fill(Path(roundedRect: grille, cornerRadius: h * 0.03), with: .color(.white.opacity(0.1)))
        }

        // the socket on the right side, and the cable
        let socketY = body.minY + h * 0.145
        context.fill(Path(roundedRect: CGRect(x: body.maxX - w * 0.012, y: socketY - h * 0.05, width: w * 0.012, height: h * 0.1), cornerRadius: 2),
                     with: .color(.black.opacity(0.6)))
        var cable = context
        cable.opacity = state.cable
        let gap = w * 0.07 * CGFloat(1 - state.plug)
        let tip = CGRect(x: body.maxX - w * 0.012 + gap, y: socketY - h * 0.035, width: w * 0.03, height: h * 0.07)
        let plug = CGRect(x: tip.maxX, y: socketY - h * 0.06, width: w * 0.06, height: h * 0.12)
        var wire = Path()
        wire.move(to: CGPoint(x: plug.maxX, y: socketY))
        wire.addCurve(to: CGPoint(x: body.maxX + w * 0.19, y: body.maxY + h * 0.28),
                      control1: CGPoint(x: plug.maxX + w * 0.08, y: socketY),
                      control2: CGPoint(x: body.maxX + w * 0.16, y: body.maxY - h * 0.2))
        cable.stroke(wire, with: .color(Color(red: 0.3, green: 0.3, blue: 0.33)), style: StrokeStyle(lineWidth: h * 0.035, lineCap: .round))
        cable.fill(Path(roundedRect: tip, cornerRadius: 2), with: .color(Color(red: 0.75, green: 0.72, blue: 0.62)))
        cable.fill(Path(roundedRect: plug, cornerRadius: h * 0.025), with: .color(Color(red: 0.4, green: 0.4, blue: 0.44)))
    }
}
