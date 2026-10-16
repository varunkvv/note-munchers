import NoteCore
import SwiftUI

/// "look who ate well today": the munchers he fed this session, full and happy,
/// growing from their size before the session to their size now. New ones get a
/// sparkle. It's made to show a grown-up: the voice says so, and there's a big hand
/// for a high five. Then two equal choices, "one more round" and "all done", and
/// both get the same little celebration. No text, no numbers.
struct SessionEndView: View {
    let summary: SessionSummary
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    @State private var highFives = 0
    @State private var choice: Choice?

    enum Choice { case oneMore, allDone }

    struct Fed: Identifiable {
        let id: ItemID
        let before: Double
        let after: Double
        let isNew: Bool
    }

    /// Every note he played, in the order first played. New = met for the first time
    /// this session (it hatched before its intro).
    static func fed(_ summary: SessionSummary) -> [Fed] {
        let new = Set(summary.screens.filter(\.wasIntro).flatMap { $0.notes.map(\.itemID) })
        return summary.practiced.map { Fed(id: $0.id, before: $0.fluencyBefore, after: $0.fluencyAfter, isNew: new.contains($0.id)) }
    }

    var body: some View {
        let fed = Self.fed(summary)
        GeometryReader { proxy in
            let columns = max(1, min(fed.count, Int(proxy.size.width / 230)))
            let rows = (fed.count + columns - 1) / columns
            let room = proxy.size.height - 220
            // a session feeds at most the lesson's notes (23 in level 3), so rows shrink to fit without scrolling
            let height = min(260, max(60, (room - 40) / CGFloat(max(1, rows)) - 20))
            let button = min(150, proxy.size.width * 0.17)
            let cell = (proxy.size.width - 64 - 20 * CGFloat(columns - 1)) / CGFloat(columns)
            ZStack {
                Theme.paper.ignoresSafeArea()
                VStack(spacing: 16) {
                    // rows of equal cells, each row centred, so a short last row sits in the middle
                    VStack(spacing: 20) {
                        ForEach(Array(stride(from: 0, to: fed.count, by: columns)), id: \.self) { first in
                            HStack(spacing: 20) {
                                ForEach(fed[first..<min(first + columns, fed.count)]) { item in
                                    muncher(item).frame(width: cell, height: height)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity, maxHeight: room, alignment: .center)

                    HStack(spacing: button * 0.45) {
                        choiceButton(.oneMore, symbol: "arrow.clockwise", color: Theme.button, size: button)
                        HighFiveHand(count: highFives, size: button * 1.1) {
                            highFives += 1
                            model.sounds.clap()
                            model.voice.say(.highFive)
                        }
                        choiceButton(.allDone, symbol: "house.fill", color: Color(red: 0.38, green: 0.62, blue: 0.95), size: button)
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .onAppear {
            if lastEndedByKid {
                model.voice.say(fed.isEmpty ? .seeYou : .lookAndShow)
            } else {
                // NoteCore already said "look who ate well today"
                model.voice.say(.showGrownUp)
            }
            if reduceMotion {
                grown = true
            } else {
                withAnimation(.spring(duration: 1.4, bounce: 0.45).delay(0.7)) { grown = true }
            }
        }
    }

    private var lastEndedByKid: Bool { model.lastEndedByKid }

    /// Both choices look the same size and get the same chime, sparkle and kind words.
    private func choiceButton(_ which: Choice, symbol: String, color: Color, size: CGFloat) -> some View {
        Button {
            guard choice == nil else { return }
            withAnimation(.spring(duration: 0.3, bounce: 0.5)) { choice = which }
            model.sounds.chime()
            model.voice.say(which == .oneMore ? .oneMore : .allDone)
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                which == .oneMore ? model.oneMoreRound() : model.allDone()
            }
        } label: {
            ZStack {
                Circle().fill(color).shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .scaleEffect(choice == which ? 1.12 : 1)
            .overlay {
                if choice == which {
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(Theme.sparkle)
                        .offset(x: size * 0.45, y: -size * 0.45)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(choice != nil)
    }

    private func muncher(_ item: Fed) -> some View {
        GrowingMuncher(id: item.id, fluency: grown ? item.after : item.before)
            .overlay(alignment: .topTrailing) {
                if item.isNew {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Theme.sparkle)
                }
            }
    }
}

/// A big open hand for a high five with a grown-up. Each tap: clap, bounce, sparkles.
struct HighFiveHand: View {
    let count: Int
    let size: CGFloat
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.keyLit.opacity(pulse ? 0.3 : 0.18))
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(Theme.keyLit)
                    .rotationEffect(.degrees(count.isMultiple(of: 2) ? 0 : -12))
                    .scaleEffect(count.isMultiple(of: 2) ? 1 : 1.12)
                    .animation(.spring(duration: 0.3, bounce: 0.6), value: count)
            }
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.3, weight: .bold))
                        .foregroundStyle(Theme.sparkle)
                        .id(count)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: count)
        }
        .buttonStyle(.plain)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// Animates fluency itself, so the muncher is redrawn at full resolution every frame.
/// (A scaleEffect on the Canvas came out blurry: it was rasterized at the small size.)
struct GrowingMuncher: View, Animatable {
    let id: ItemID
    var fluency: Double

    var animatableData: Double {
        get { fluency }
        set { fluency = newValue }
    }

    var body: some View {
        MuncherView(id: id, pose: MuncherPose(fluency: fluency, full: true))
    }
}
