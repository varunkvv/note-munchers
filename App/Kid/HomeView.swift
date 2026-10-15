import NoteCore
import SwiftUI

/// The kid's start screen: a big play button and his munchers. No text.
struct HomeView: View {
    let model: AppModel

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Theme.paper.ignoresSafeArea()
                if landscape {
                    HStack(spacing: 0) {
                        PlayButton(size: s * 0.3) { model.startPractice() }
                            .frame(width: proxy.size.width * 0.34)
                        MunchersGrid(model: model)
                    }
                } else {
                    VStack(spacing: 0) {
                        PlayButton(size: s * 0.3) { model.startPractice() }
                            .frame(height: proxy.size.height * 0.34)
                        MunchersGrid(model: model)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            ParentGate { model.showParent = true }
        }
    }
}

struct PlayButton: View {
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.button)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: size * 0.04)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}

/// Every muncher he has, in curriculum order. Notes that are unlocked but not met yet
/// wait as eggs. Each has a tiny staff with its note under it (no letters).
struct MunchersGrid: View {
    let model: AppModel

    struct Entry: Identifiable {
        let id: ItemID
        let fluency: Double
        let isEgg: Bool
    }

    static func entries(_ engine: MasteryEngine) -> [Entry] {
        let unit = engine.unit
        let waiting = Set(unit.newItems.prefix(engine.unlockedCount(unit.number)).map(\.id))
        return engine.curriculum.allItems.compactMap { item in
            let stats = engine.stats(for: item.id)
            if stats.attempts > 0 || engine.state.introduced.contains(item.id) {
                return Entry(id: item.id, fluency: stats.peakFluency, isEgg: false)
            }
            return waiting.contains(item.id) ? Entry(id: item.id, fluency: 0, isEgg: true) : nil
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 18)], spacing: 22) {
                ForEach(Self.entries(model.engine)) { entry in
                    MuncherCard(entry: entry, sounds: model.sounds)
                }
            }
            .padding(28)
        }
        .scrollIndicators(.hidden)
    }
}

struct MuncherCard: View {
    let entry: MunchersGrid.Entry
    let sounds: Sounds
    @State private var jiggle = false

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if entry.isEgg {
                    Canvas { context, size in
                        EggPainter(look: MuncherLook(id: entry.id), progress: 0)
                            .draw(in: &context, rect: CGRect(origin: .zero, size: size), id: entry.id)
                    }
                } else {
                    MuncherView(id: entry.id, pose: MuncherPose(fluency: entry.fluency, mouthOpen: jiggle ? 0.7 : 0))
                }
            }
            .frame(height: 130)
            .rotationEffect(.degrees(jiggle ? 6 : 0), anchor: .bottom)
            if let item = Curriculum.standard.item(entry.id) {
                StaffView(spec: StaffSpec(items: [item], layout: item.clef == .treble ? .treble : .bass), item: item)
                    .frame(height: 92)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.paper))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.keyEdge.opacity(0.2)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !entry.isEgg else { return }
            sounds.chomp()
            withAnimation(.spring(duration: 0.2, bounce: 0.6)) { jiggle = true }
            Task {
                try? await Task.sleep(for: .seconds(0.3))
                withAnimation(.spring(duration: 0.3, bounce: 0.5)) { jiggle = false }
            }
        }
    }
}
