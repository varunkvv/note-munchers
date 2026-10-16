#if DEBUG
import NoteCore
import SwiftUI

/// `-demoScreen gallery -demoLesson <id>`: a dozen screens the generator makes for a
/// lesson (every note met, at the lesson's smallest and largest size), on the practice
/// screen's staff, to check drawing (ledger lines, bar lines, the grand staff, key
/// signatures) in one screenshot.
struct StaffGallery: View {
    let lesson: Lesson

    var body: some View {
        let items = Self.screens(lesson)
        let spec = { (item: PracticeItem) in StaffSpec(lesson: lesson, layout: item.layout) }
        let grand = lesson.layout == .grand
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: grand ? 2 : 3), spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    StaffView(spec: spec(item), item: item)
                        .frame(height: grand ? 300 : 170)
                        .background(Theme.paper)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                }
            }
            .padding(16)
        }
        .background(Color(white: 0.9))
    }

    static func screens(_ lesson: Lesson) -> [PracticeItem] {
        var engine = MasteryEngine(state: MasteryState(seed: 3))
        engine.moveToLesson(lesson.id)
        engine = DemoRunner.meetEverything(engine)
        var rng = SeededRandom(seed: 5)
        var items: [PracticeItem] = []
        for size in [lesson.sizes.lowerBound, lesson.sizes.upperBound] {
            var state = engine.state
            state.screenSize = size
            var sized = MasteryEngine(config: engine.config, state: state)
            for _ in 0..<6 { items.append(sized.pickScreen(using: &rng).item) }
        }
        return items
    }
}
#endif
