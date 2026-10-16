import NoteCore
import SwiftUI

/// The kid's start screen: a big "Play!" button and his collection, in two groups with
/// short headings: "My munchers" and "Hatching soon" (eggs). A few plain words, big.
///
/// It's calm but alive: the play button breathes slowly, and every few seconds one
/// muncher blinks, looks around or bobs, or one egg wobbles. Never two at once. Tapping
/// a muncher makes it hop and plays its note. Nothing moves with reduce motion, and the
/// idle stops while the screen isn't showing.
///
/// First launch: three picture cards (`IntroCards`) explain the game before the first
/// round. The parent can show them again from the parent area.
struct HomeView: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(IntroCards.seenKey) private var introSeen = false
    /// the intro card showing, nil = no intro
    @State private var introCard: Int?
    /// the one muncher or egg doing something right now
    @State private var idle: IdleCue?

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Theme.paper.ignoresSafeArea()
                if landscape {
                    HStack(spacing: 0) {
                        VStack(spacing: s * 0.06) {
                            PlayButton(size: s * (model.canPlaySongs ? 0.27 : 0.3), breathing: idleOn) { model.startPractice() }
                            if model.canPlaySongs {
                                SongTimeButton(size: s * 0.13) { model.startSong() }
                            }
                        }
                        .frame(width: proxy.size.width * 0.34)
                        MunchersGrid(model: model, idle: idle, onTap: tap)
                    }
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: s * 0.08) {
                            PlayButton(size: s * 0.26, breathing: idleOn) { model.startPractice() }
                            if model.canPlaySongs {
                                SongTimeButton(size: s * 0.13) { model.startSong() }
                            }
                        }
                        .frame(height: proxy.size.height * 0.34)
                        MunchersGrid(model: model, idle: idle, onTap: tap)
                    }
                }
            }
        }
        .overlay {
            if let card = introCard {
                IntroCards(card: card, sounds: model.sounds) { next in
                    if let next {
                        introCard = next
                    } else {
                        introSeen = true
                        introCard = nil
                        model.startPractice()
                    }
                }
                .transition(.opacity)
            }
        }
        // over the intro too, so a parent setting up can still get to settings
        .overlay(alignment: .topTrailing) {
            ParentGate { model.showParent = true }
        }
        .onAppear {
            introCard = firstIntroCard
        }
        .onChange(of: introSeen) { _, seen in
            // the parent asked to see the intro again
            if !seen { introCard = 0 }
        }
        .task(id: idleOn) {
            guard idleOn else {
                idle = nil
                return
            }
            await runIdle()
        }
    }

    /// Idle movement only while he can see the screen.
    private var idleOn: Bool {
        !reduceMotion && scenePhase == .active && !model.showParent && introCard == nil
    }

    private var firstIntroCard: Int? {
        #if DEBUG
        // demo runs don't show the intro unless asked (-demoIntro 1|2|3 opens that card),
        // so other screenshot runs of home stay as they were
        if model.demo.isActive { return IntroCards.demoCard }
        #endif
        return introSeen ? nil : 0
    }

    /// Every 2.5-4s one muncher blinks, looks around or bobs, or one egg wobbles.
    private func runIdle() async {
        var last: ItemID?
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 2.5...4)))
            guard !Task.isCancelled else { return }
            // a hop he asked for is still going
            guard idle == nil else { continue }
            let entries = MunchersGrid.entries(model.engine)
            guard let pick = entries.filter({ $0.id != last }).randomElement() ?? entries.first else { continue }
            last = pick.id
            let kind: IdleCue.Kind = pick.isEgg ? .wobble : [.blink, .blink, .glance, .bob].randomElement()!
            let cue = IdleCue(id: pick.id, kind: kind, start: .now)
            idle = cue
            #if DEBUG
            print("home: idle \(kind) \(pick.id)")
            #endif
            try? await Task.sleep(for: .seconds(kind.length))
            if idle == cue { idle = nil }
        }
    }

    /// His collection, so he can play with it: a muncher hops and its note plays, an
    /// egg wobbles.
    private func tap(_ entry: MunchersGrid.Entry) {
        let cue = IdleCue(id: entry.id, kind: entry.isEgg ? .wobble : .hop, start: .now)
        if !entry.isEgg { model.sounds.play([entry.key.pitch]) }
        guard !reduceMotion || !entry.isEgg else { return }
        idle = cue
        Task {
            try? await Task.sleep(for: .seconds(cue.kind.length))
            if idle == cue { idle = nil }
        }
    }
}

/// One small thing one muncher or egg does on home.
struct IdleCue: Equatable {
    enum Kind {
        case blink, glance, bob, wobble, hop

        var length: Double {
            switch self {
            case .blink: 0.32
            case .glance: 2.2
            case .bob: 1.1
            case .wobble: 1.6
            case .hop: 0.75
            }
        }
    }

    let id: ItemID
    let kind: Kind
    let start: Date
}

/// The big green button with "Play!" under it. Breathes slowly (a 4% swell every 3.4s)
/// to invite a tap.
struct PlayButton: View {
    let size: CGFloat
    var breathing = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: size * 0.1) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !breathing)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let swell = breathing ? (1 - cos(t * 2 * .pi / 3.4)) / 2 : 0
                    ZStack {
                        Circle().fill(Theme.button)
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        Image(systemName: "play.fill")
                            .font(.system(size: size * 0.42, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: size * 0.04)
                    }
                    .frame(width: size, height: size)
                    .scaleEffect(1 + 0.04 * swell)
                }
                Text("Play!")
                    .font(Theme.kidFont(size * 0.22, weight: .heavy))
                    .foregroundStyle(Theme.button.mix(with: .black, by: 0.25))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Song time, under Play!: smaller, its own colour, and still (Play! keeps the only
/// pulse). It's only there once he has notes to make songs from, never shown locked.
struct SongTimeButton: View {
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: size * 0.12) {
                ZStack {
                    Circle().fill(Theme.song)
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
                Text("Song time!")
                    .font(Theme.kidFont(size * 0.3, weight: .heavy))
                    .foregroundStyle(Theme.song.mix(with: .black, by: 0.3))
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// His collection in two groups. "Hatching soon": notes that are unlocked but waiting
/// for their intro, as eggs. "My munchers": one per note he has met, treble first, low
/// to high, then bass. Each has a tiny staff with its note under it (no letters).
/// Before he has any munchers, the eggs say what they are in one line.
struct MunchersGrid: View {
    let model: AppModel
    var idle: IdleCue?
    var onTap: (Entry) -> Void = { _ in }

    struct Entry: Identifiable {
        let key: NoteKey
        let fluency: Double
        let isEgg: Bool
        var id: ItemID { key.id }
    }

    static func entries(_ engine: MasteryEngine) -> [Entry] {
        let met = engine.metNotes.map { Entry(key: $0, fluency: engine.stats(for: $0).peakFluency, isEgg: false) }
        let eggs = engine.pendingIntros.filter { !engine.metNotes.contains($0) }.map { Entry(key: $0, fluency: 0, isEgg: true) }
        return (met + eggs).sorted { $0.key < $1.key }
    }

    var body: some View {
        let all = Self.entries(model.engine)
        let munchers = all.filter { !$0.isEgg }
        let eggs = all.filter(\.isEgg)
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    // eggs first: there are only ever a few, and they stay in sight
                    // however many munchers he has
                    if !eggs.isEmpty {
                        group("Hatching soon", eggs, line: munchers.isEmpty ? "Learn a new note to hatch an egg!" : nil)
                    }
                    if !munchers.isEmpty {
                        group("My munchers", munchers)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 32)
                // a short collection sits in the middle, next to the play button
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func group(_ title: String, _ entries: [Entry], line: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.kidFont(36))
                    .foregroundStyle(Theme.kidText)
                if let line {
                    Text(line)
                        .font(Theme.kidFont(26, weight: .semibold))
                        .foregroundStyle(Theme.kidTextSoft)
                }
            }
            .padding(.leading, 6)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 18)], spacing: 22) {
                ForEach(entries) { entry in
                    MuncherCard(entry: entry, cue: idle?.id == entry.id ? idle : nil) { onTap(entry) }
                }
            }
        }
    }
}

/// One muncher (or egg) over its note. Still, except while it has a cue: then it runs
/// that one small move on its own timeline and stops again.
struct MuncherCard: View {
    let entry: MunchersGrid.Entry
    var cue: IdleCue?
    var onTap: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: cue == nil)) { timeline in
                let t = cue.map { timeline.date.timeIntervalSince($0.start) } ?? 0
                let move = Move(kind: cue?.kind, t: t, reduceMotion: reduceMotion)
                Group {
                    if entry.isEgg {
                        Canvas { context, size in
                            EggPainter(look: MuncherLook(id: entry.id), progress: 0, rock: move.rock)
                                .draw(in: &context, rect: CGRect(origin: .zero, size: size), id: entry.id)
                        }
                    } else {
                        MuncherView(id: entry.id, pose: move.pose(fluency: entry.fluency))
                    }
                }
                .offset(y: -move.lift)
            }
            .frame(height: 130)
            NoteStaff(key: entry.key)
                .frame(height: 92)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.paper))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.keyEdge.opacity(0.2)))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    /// Where a cue is at time `t`. Slow and small on purpose.
    struct Move {
        var rock = 0.0
        var lift = 0.0
        var blink = 0.0
        var glance = 0.0
        var mouthOpen = 0.0
        var squash = 0.0

        init(kind: IdleCue.Kind?, t: Double, reduceMotion: Bool) {
            guard let kind else { return }
            let x = min(1, max(0, t / kind.length))
            switch kind {
            case .blink:
                blink = sin(.pi * x)
            case .glance:
                // look right, then left, then back to the usual
                func ease(_ a: Double, _ b: Double) -> Double {
                    let u = min(1, max(0, (x - a) / (b - a)))
                    return u * u * (3 - 2 * u)
                }
                glance = ease(0.05, 0.22) - 2 * ease(0.42, 0.6) + ease(0.8, 0.97)
            case .bob:
                lift = 6 * sin(.pi * x)
            case .wobble:
                // two soft rocks, dying away (about 5 degrees at most)
                rock = 0.09 * sin(2 * .pi * 2 * x) * (1 - x)
            case .hop:
                // a happy hop with a grin, a little squash on landing
                mouthOpen = x < 0.8 ? 0.6 : 0
                if !reduceMotion {
                    let air = 0.7
                    lift = x < air ? 22 * sin(.pi * x / air) : 0
                    squash = x >= air ? 0.5 * sin(.pi * (x - air) / (1 - air)) : 0
                }
            }
            if reduceMotion {
                rock = 0
                lift = 0
            }
        }

        func pose(fluency: Double) -> MuncherPose {
            var pose = MuncherPose(fluency: fluency, mouthOpen: mouthOpen, squash: squash)
            pose.blink = blink
            pose.glance = glance
            return pose
        }
    }
}

/// One note on a small staff of its own clef. F# is read from the G major key
/// signature, the way he meets it in practice.
struct NoteStaff: View {
    let key: NoteKey

    var body: some View {
        let item = PracticeItem(key, keySignature: key.pitch.isWhiteKey ? .none : .gMajor)
        StaffView(spec: StaffSpec(item: item), item: item)
    }
}

// MARK: - first launch intro

/// Three picture cards before his first round, each a big picture and a few words:
/// "Look at the note" (a staff with one note), "Play it on the piano" (the keyboard
/// picture, a finger pressing the lit key) and "Feed the munchers!" (a muncher gobbling
/// a note). A big arrow moves on, "Let's go!" on the last card starts the round. No
/// timers: he goes at his own pace. Shown once; the parent area can show it again.
struct IntroCards: View {
    let card: Int
    let sounds: Sounds
    /// next card, or nil after "Let's go!"
    let onNext: (Int?) -> Void

    static let seenKey = "introSeen"
    static let count = 3
    /// the note the cards show: G above middle C, his first treble note
    static let note = NoteKey(.treble, Pitch("G4")!)

    #if DEBUG
    /// `-demoIntro <n>` opens the intro on card n (1-3) in a demo run. simctl can't tap.
    static var demoCard: Int? {
        guard let n = UserDefaults.standard.string(forKey: "demoIntro").flatMap(Int.init), (1...count).contains(n) else { return nil }
        return n - 1
    }
    #endif

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var words: String {
        ["Look at the note", "Play it on the piano", "Feed the munchers!"][card]
    }

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let picture = CGSize(width: min(proxy.size.width * 0.62, s * 0.95), height: proxy.size.height * 0.46)
            ZStack {
                Theme.paper.ignoresSafeArea()
                VStack(spacing: s * 0.04) {
                    Spacer(minLength: 0)
                    ZStack {
                        switch card {
                        case 0: IntroNote()
                        case 1: IntroPiano(sounds: sounds)
                        default: IntroGobble(sounds: sounds)
                        }
                    }
                    .frame(width: picture.width, height: picture.height)
                    Text(words)
                        .font(Theme.kidFont(s * 0.075, weight: .heavy))
                        .foregroundStyle(Theme.kidText)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                    nextButton(s: s)
                    dots(s: s)
                        .padding(.bottom, s * 0.04)
                }
                .frame(maxWidth: .infinity)
                .id(card)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 50)),
                    removal: .opacity.combined(with: .offset(x: -50))
                ))
            }
        }
        .animation(.easeInOut(duration: 0.45), value: card)
    }

    @ViewBuilder private func nextButton(s: CGFloat) -> some View {
        let last = card == Self.count - 1
        Button {
            sounds.chime()
            onNext(last ? nil : card + 1)
        } label: {
            Group {
                if last {
                    Text("Let's go!")
                        .font(Theme.kidFont(s * 0.065, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, s * 0.08)
                        .frame(height: s * 0.15)
                        .background(Capsule().fill(Theme.button).shadow(color: .black.opacity(0.15), radius: 6, y: 3))
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: s * 0.06, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: s * 0.15, height: s * 0.15)
                        .background(Circle().fill(Theme.button).shadow(color: .black.opacity(0.15), radius: 6, y: 3))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dots(s: CGFloat) -> some View {
        HStack(spacing: s * 0.018) {
            ForEach(0..<Self.count, id: \.self) { i in
                Circle()
                    .fill(i == card ? Theme.kidText.opacity(0.7) : Theme.kidText.opacity(0.18))
                    .frame(width: s * 0.016, height: s * 0.016)
            }
        }
    }
}

/// Card 1: a big staff, and its note fades in once.
private struct IntroNote: View {
    @State private var shown = false

    var body: some View {
        let item = PracticeItem(IntroCards.note, keySignature: .none)
        let spec = StaffSpec(item: item)
        ZStack {
            StaffView(spec: spec, item: nil)
            StaffView(spec: spec, item: item)
                .opacity(shown ? 1 : 0)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.paperHighContrast))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.keyEdge.opacity(0.2), lineWidth: 2))
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.5)) { shown = true }
        }
    }
}

/// Card 2: the keyboard picture, and a finger slowly pressing the note's key, which
/// lights while it's down. One press every 2.6s. The note sounds on the first press.
private struct IntroPiano: View {
    let sounds: Sounds

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var start = Date()

    private static let range = Pitch("C4")!...Pitch("C5")!
    private static let cycle = 2.6

    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(width: proxy.size.width, height: proxy.size.height * 0.8)
            let layout = KeyLayout(range: Self.range, size: size)
            let key = layout.rect(IntroCards.note.pitch)
            let left = (size.width - layout.width) / 2
            let top = proxy.size.height * 0.2 + (size.height - layout.height) / 2
            let finger = layout.whiteWidth * 1.9
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
                let down = reduceMotion ? 1 : press(timeline.date.timeIntervalSince(start))
                ZStack(alignment: .topLeading) {
                    KeyboardPicture(range: Self.range, lit: down > 0.9 ? [IntroCards.note.pitch] : [])
                        .frame(width: size.width, height: size.height)
                        .offset(y: proxy.size.height * 0.2)
                    hand(size: finger)
                        .frame(width: finger * 1.3, height: finger * 1.3, alignment: .bottom)
                        // the fingertip (right of the glyph's middle, at its bottom) on the
                        // white part of the key when down, lifted when up
                        .position(x: left + key.midX - finger * 0.14, y: top + layout.height * 0.84 - finger * 0.65 - (1 - down) * finger * 0.5)
                }
            }
        }
        .onAppear {
            start = Date()
            Task {
                try? await Task.sleep(for: .seconds(reduceMotion ? 0.3 : 0.9))
                sounds.play([IntroCards.note.pitch])
            }
        }
    }

    /// 0 up ... 1 down. Down by 0.9s into each cycle, held, up again by 1.9s.
    private func press(_ t: Double) -> Double {
        let x = t.truncatingRemainder(dividingBy: Self.cycle)
        func ease(_ a: Double, _ b: Double) -> Double {
            let u = min(1, max(0, (x - a) / (b - a)))
            return u * u * (3 - 2 * u)
        }
        return ease(0.4, 0.85) - ease(1.5, 1.95)
    }

    private func hand(size: CGFloat) -> some View {
        ZStack {
            Image(systemName: "hand.point.down.fill")
                .foregroundStyle(Color(red: 1, green: 0.86, blue: 0.72))
            Image(systemName: "hand.point.down")
                .foregroundStyle(Theme.kidText)
        }
        .font(.system(size: size, weight: .regular))
    }
}

/// Card 3: a muncher gobbling a note. The note flies in from the left, the mouth opens,
/// chomp, then it rests and smiles. One gobble every 3.2s, a chomp sound on the first.
private struct IntroGobble: View {
    let sounds: Sounds

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var start = Date()

    private static let cycle = 3.2
    private static let look = MuncherLook(id: "intro:muncher", colorIndex: 5)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start).truncatingRemainder(dividingBy: Self.cycle)
                var pose = MuncherPose(fluency: 0.5)
                if reduceMotion {
                    pose.mouthOpen = 0.6
                } else if t < 1.1 {
                    // in flight: the mouth opens as the note gets close
                    let f = t / 1.1
                    pose.noteFlight = f
                    pose.mouthOpen = min(1, max(0, (f - 0.3) / 0.6)) * 0.9
                } else if t < 1.45 {
                    // chomp
                    let c = (t - 1.1) / 0.35
                    pose.squash = 0.6 * sin(.pi * c)
                }
                // the muncher on the right, so the note has room to fly in
                let side = min(size.height, size.width * 0.55)
                let rect = CGRect(x: size.width * 0.12, y: (size.height - side) / 2, width: size.width * 0.88, height: side)
                var painter = MuncherPainter(look: Self.look, pose: pose)
                painter.growth = 0.9...1
                painter.draw(in: &context, rect: rect)
            }
        }
        .onAppear {
            start = Date()
            guard !reduceMotion else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.1))
                sounds.chomp()
            }
        }
    }
}
