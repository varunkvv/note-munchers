#if DEBUG
import Foundation
import NoteCore

/// `-demoProgress YES`: three weeks of made-up practice through the real engine, so
/// munchers, the end screen and the dashboard trends have something to show.
/// About 18 items a day, slowly getting faster and more often right first try.
enum DemoHistory {
    @MainActor
    static func seed(into store: Store, days: Int = 21, seed: UInt64 = 42) -> MasteryEngine {
        var engine = MasteryEngine(state: MasteryState(seed: seed))
        var rng = SeededRandom(seed: seed)
        func roll() -> Double { Double(rng.next() >> 11) * 0x1p-53 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // leave today empty, so a demo session today is the newest
        for day in stride(from: days, through: 1, by: -1) {
            guard let start = calendar.date(byAdding: .day, value: -day, to: today)?.addingTimeInterval(17 * 3600) else { continue }
            let skill = 1 - Double(day) / Double(days)
            engine.beginSession(day: AppModel.today(start))
            var summary = SessionSummary(startLesson: engine.lesson.id)
            var clock = 0.0
            for _ in 0..<12 {
                let lesson = engine.lesson
                let pick = engine.pickScreen(using: &rng)
                var notes: [AttemptResult] = []
                let keys = pick.item.notes.flatMap(\.keys)
                for (i, key) in keys.enumerated() {
                    let firstTry = pick.intro != nil || roll() < 0.6 + 0.37 * skill
                    let response = max(0.7, (4.4 - 3.3 * skill) * (0.7 + 0.6 * roll()))
                    notes.append(AttemptResult(
                        itemID: key.id, lesson: lesson.id, level: lesson.level, wasIntro: pick.intro == key,
                        firstTry: firstTry, wrongPresses: firstTry ? 0 : 1, hints: firstTry ? .none : .wobble,
                        responseTime: response, inLine: i > 0 && pick.intro == nil && key != keys[i - 1]
                    ))
                    clock += response + 0.5
                }
                let screen = ScreenResult(screenID: pick.item.id, lesson: lesson.id, wasIntro: pick.intro != nil, notes: notes, size: pick.size)
                let update = engine.record(screen)
                clock += 1.5
                for note in notes { store.addAttempt(note, at: start.addingTimeInterval(clock), commit: false) }
                summary.screensPlayed += 1
                summary.screens.append(screen)
                for note in notes where !note.wasIntro {
                    summary.notesPlayed += 1
                    summary.firstTryNotes += note.firstTry ? 1 : 0
                }
                summary.unlocked += update.unlocked
                if let done = update.completedLesson { summary.completedLessons.append(done) }
            }
            summary.activeDuration = clock
            summary.endLesson = engine.lesson.id
            store.addSession(summary, startedAt: start, endedAt: start.addingTimeInterval(clock))
        }
        store.saveMastery(engine.state, settings: ParentSettings(engine.config))
        print("demo: seeded \(days) days, now lesson \(engine.lesson.id), \(engine.allProgress.count) notes played")
        return engine
    }
}
#endif
