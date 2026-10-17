import NoteCore
import SwiftUI

/// Song time: the title card, the song's pages, the end card.
///
/// Calm on purpose: only the page fade moves in the staff area, one muncher at a time
/// moves in the lane, and reduce motion makes everything still or instant. Text is only
/// "Song time!", the title ("Mystery song!" for a familiar tune), "Let's play!", "One
/// more time!" over the come-back bar, "You played it!" (or the tune's name: "You played
/// Mary Had a Little Lamb!"), "Listen", "New song", "All done".
struct SongView: View {
    let controller: SongController
    let input: InputHub

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            switch controller.phase {
            case .title:
                SongTitleCard(controller: controller).transition(.opacity)
            case .playing, .ending:
                SongPageView(controller: controller, input: input).transition(.opacity)
            case .end, .listening:
                SongEndCard(controller: controller).transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: controller.phase == .title)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: controller.phase == .end || controller.phase == .listening)
        .overlay {
            if controller.isPaused, controller.phase == .playing {
                TurnOnPianoView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: controller.isPaused)
        .onAppear { controller.open() }
    }
}

// MARK: - title card

/// The band on a coloured rug, the song's name, "Let's play!" and the door.
struct SongTitleCard: View {
    let controller: SongController

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            VStack(spacing: s * 0.04) {
                Spacer(minLength: 0)
                Text(controller.song.title)
                    .font(Theme.kidFont(s * 0.1, weight: .heavy))
                    .foregroundStyle(Theme.kidText)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                BandView(controller: controller, onRug: true)
                    .frame(width: min(proxy.size.width * 0.8, s * 1.1), height: s * 0.42)
                SongButton(title: "Let's play!", symbol: "play.fill", size: s * 0.17, color: Theme.song) {
                    controller.start()
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            DoneForNowButton(action: controller.leave)
        }
    }
}

// MARK: - song pages

/// A page of the song: the staff (two systems on one staff, one grand system), the
/// keyboard picture under it, and the lane with the band, the page dots, the play
/// button and the door. A page turn is a 0.3s cross-fade. Nothing scrolls, no cursor.
struct SongPageView: View {
    let controller: SongController
    let input: InputHub

    @AppStorage(StaffStyle.Key.size) private var staffSize = StaffStyle().size
    @AppStorage(StaffStyle.Key.lineThickness) private var lineThickness = StaffStyle().lineThickness
    @AppStorage(StaffStyle.Key.spaceTint) private var spaceTint = StaffStyle().spaceTint
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var style: StaffStyle {
        StaffStyle(size: staffSize, lineThickness: lineThickness, spaceTint: spaceTint, highContrast: contrast == .increased).clamped
    }

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width >= proxy.size.height
            ZStack {
                style.paper.ignoresSafeArea()
                if landscape {
                    HStack(spacing: 0) {
                        staffColumn
                        lane.frame(width: laneWidth(screen: proxy.size.width))
                    }
                } else {
                    VStack(spacing: 0) {
                        staffColumn.frame(height: proxy.size.height * 0.8)
                        lane.frame(height: proxy.size.height * 0.2)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            DoneForNowButton(action: controller.leave)
        }
        #if DEBUG
        .overlay(alignment: .bottom) {
            if input.debugKeyboardOn {
                DebugKeyboard(input: input, range: controller.keyboardRange)
            }
        }
        #endif
    }

    private var lane: some View {
        BandView(controller: controller, onRug: false)
            .padding(.top, 110) // the door's corner
            .padding(.bottom, ListenButton.room + 30)
            .background(RoundedRectangle(cornerRadius: 28).fill(Theme.lane))
            .padding(12)
            .overlay(alignment: .bottom) {
                VStack(spacing: 18) {
                    PageDots(count: controller.pages.count, current: controller.page)
                    ListenButton(enabled: controller.canHear, action: controller.hearIt)
                }
                .padding(.bottom, 30)
            }
    }

    /// Like practice: the room the staff doesn't need at its full line gap, up to 30%.
    private func laneWidth(screen width: CGFloat) -> CGFloat {
        let staff = CGFloat(controller.spec.width) * Metrics.gap * CGFloat(style.size) + 16
        return max(180, min(width * 0.3, max(width * 0.17, width - staff)))
    }

    private var staffColumn: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    systems
                        .id(controller.page)
                        .transition(.opacity)
                    // the bar the band helped with, once more before the end
                    if controller.isComeBackPage {
                        Text("One more time!")
                            .font(Theme.kidFont(min(44, proxy.size.height * 0.06), weight: .heavy))
                            .foregroundStyle(Theme.kidTextSoft)
                            .padding(.top, 8)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: controller.page)
                .padding(.horizontal, 8)
                .padding(.top, 12)
                SongHintBand(controller: controller)
                    .frame(height: proxy.size.height * 0.21)
            }
        }
    }

    private var systems: some View {
        let page = controller.currentPage
        return VStack(spacing: 0) {
            ForEach(page.systems.indices, id: \.self) { s in
                let first = controller.page == 0 && s == 0
                let last = controller.page == controller.pages.count - 1 && s == page.systems.count - 1
                StaffView(spec: controller.spec, item: page.systems[s], doneCount: controller.doneCount(system: s),
                          effects: controller.effects[s], style: style, gap: Metrics.gap * CGFloat(style.size),
                          showsMeter: first, endsPiece: last)
            }
        }
    }
}

/// Under the staff: the keyboard picture while the page plays (keys lighting as they
/// sound) or when a key is lit to help.
struct SongHintBand: View {
    let controller: SongController

    var body: some View {
        ZStack {
            if let lit = controller.playingKeys ?? (controller.keyboardHint.isEmpty ? nil : controller.keyboardHint) {
                KeyboardPicture(range: controller.keyboardRange, lit: lit)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controller.keyboardHint)
        .animation(.easeInOut(duration: 0.25), value: controller.playingKeys == nil)
    }
}

/// Which page of the song he's on. Nothing when the song is one page.
struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        if count > 1 {
            HStack(spacing: 12) {
                ForEach(0..<count, id: \.self) { i in
                    Circle()
                        .fill(i == current ? Theme.song : Theme.keyEdge.opacity(0.25))
                        .frame(width: 16, height: 16)
                }
            }
        }
    }
}

// MARK: - end card

/// The band bowing, the song's name, "You played it!" (a familiar tune's name revealed
/// here, "You played Jingle Bells!"), then Listen, New song and All done, the same size. Listen plays his song with the backing while the band hops on
/// the beat. One recorded line (show a grown-up), nothing new.
struct SongEndCard: View {
    let controller: SongController

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let button = min(150, proxy.size.width * 0.15)
            VStack(spacing: s * 0.03) {
                Spacer(minLength: 0)
                Text(controller.song.title)
                    .font(Theme.kidFont(s * 0.075, weight: .heavy))
                    .foregroundStyle(Theme.kidText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                BandView(controller: controller, onRug: true)
                    .frame(width: min(proxy.size.width * 0.75, s * 1.0), height: s * 0.36)
                Text(controller.written.tune.map { "You played \($0)!" } ?? "You played it!")
                    .font(Theme.kidFont(s * 0.06, weight: .heavy))
                    .foregroundStyle(Theme.song.mix(with: .black, by: 0.3))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
                HStack(alignment: .top, spacing: button * 0.5) {
                    SongButton(title: "Listen", symbol: "speaker.wave.2.fill", size: button, color: Theme.keyLit,
                               enabled: controller.phase == .end, action: controller.listen)
                    SongButton(title: "New song", symbol: "music.note", size: button, color: Theme.song, action: controller.newSong)
                    SongButton(title: "All done", symbol: "house.fill", size: button, color: Theme.homeButton, action: controller.leave)
                }
                .padding(.top, s * 0.02)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// A big round button with its word under it, in a darker shade of its colour.
struct SongButton: View {
    let title: String
    let symbol: String
    let size: CGFloat
    let color: Color
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: size * 0.08) {
                ZStack {
                    Circle().fill(color).shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
                Text(title)
                    .font(Theme.kidFont(min(40, size * 0.26), weight: .heavy))
                    .foregroundStyle(color.mix(with: .black, by: 0.3))
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }
}

// MARK: - the band

/// Three of his munchers. On each right note (and each beat of Listen) the next one in
/// the row does a small hop, so only one moves at a time. They bow together at the end.
/// In a tall lane they stand one above the other, otherwise side by side. On the title
/// and end cards they stand on a rug.
struct BandView: View {
    let controller: SongController
    let onRug: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(MuncherColors.self) private var colors
    @State private var hopStart: Date?
    @State private var hopper = 0

    static let hopLength = 0.32
    static let bowLength = 0.7

    var body: some View {
        let busy = hopStart != nil || controller.bowedAt.map { Date().timeIntervalSince($0) < Self.bowLength * controller.timeScale + 0.1 } == true
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !busy)) { timeline in
            Canvas { context, size in
                draw(&context, size: size, now: timeline.date)
            }
        }
        .onChange(of: controller.hops) { _, hops in
            hopper = (hops - 1) % max(1, controller.band.count)
            hopStart = Date()
            Task {
                try? await Task.sleep(for: .seconds(Self.hopLength * controller.timeScale + 0.05))
                if let start = hopStart, Date().timeIntervalSince(start) >= Self.hopLength * controller.timeScale { hopStart = nil }
            }
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, now: Date) {
        let band = controller.band
        guard !band.isEmpty else { return }
        let tall = size.height > size.width * 1.2
        let count = CGFloat(band.count)
        let slot = (tall ? size.height : size.width) / count
        let side = min(tall ? size.width * 0.8 : size.height * (onRug ? 0.82 : 0.9), slot * 0.92)
        if onRug {
            let rug = CGRect(x: size.width * 0.04, y: size.height * 0.72, width: size.width * 0.92, height: size.height * 0.26)
            context.fill(Path(roundedRect: rug, cornerRadius: rug.height / 2), with: .color(Theme.rug))
            context.stroke(Path(roundedRect: rug.insetBy(dx: 8, dy: 8), cornerRadius: rug.height / 2 - 8),
                           with: .color(Theme.song.opacity(0.35)), style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
        }
        let bow = controller.bowedAt.map { now.timeIntervalSince($0) / (Self.bowLength * controller.timeScale) }
        for (i, key) in band.enumerated() {
            let along = slot * (CGFloat(i) + 0.5)
            let center = tall ? CGPoint(x: size.width / 2, y: along) : CGPoint(x: along, y: onRug ? size.height * 0.84 - side / 2 : size.height / 2)
            let square = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
            var pose = MuncherPose(fluency: controller.fluency(of: key))
            var muncher = context
            if let start = hopStart, i == hopper {
                let x = min(1, now.timeIntervalSince(start) / (Self.hopLength * controller.timeScale))
                pose.mouthOpen = x < 0.9 ? 0.5 : 0
                if !reduceMotion { muncher.translateBy(x: 0, y: -side * 0.1 * sin(.pi * x)) }
            }
            if let bow {
                // a bow from the feet, then standing happy (closed smiling eyes)
                pose.full = true
                if !reduceMotion, bow < 1 {
                    let tilt = 0.32 * sin(.pi * bow)
                    let feet = CGPoint(x: square.midX, y: square.maxY)
                    muncher.translateBy(x: feet.x, y: feet.y)
                    muncher.rotate(by: .radians(-tilt))
                    muncher.translateBy(x: -feet.x, y: -feet.y)
                    pose.squash = 0.4 * sin(.pi * bow)
                }
            }
            MuncherPainter(look: colors.look(key.id), pose: pose, growth: 0.62...0.85).draw(in: &muncher, rect: square)
        }
    }
}

extension SongController {
    /// How big his muncher for this note is.
    func fluency(of key: NoteKey) -> Double { fluencies[key] ?? 0.5 }
}
