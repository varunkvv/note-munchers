#if DEBUG
import Foundation
import NoteCore

/// `-demoProgress YES`: three weeks of made-up practice through the real engine, so
/// munchers, the end screen and the dashboard trends have something to show.
/// About 18 items a day, slowly getting faster and more often right first try.
enum DemoHistory {
    /// `lesson`: the history starts there, every note of it met (else 1.1 for a new kid).
    @MainActor
    static func seed(into store: Store, days: Int = 21, seed: UInt64 = 42, lesson start: LessonID? = nil) -> MasteryEngine {
        var engine = MasteryEngine(state: MasteryState(seed: seed))
        if let start {
            engine.moveToLesson(start)
            engine = DemoRunner.meetEverything(engine)
        }
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
                // bar 2 of a pattern screen goes a bit quicker (made up, for the dashboard)
                let secondBar = pick.item.bars.count == 2 ? pick.item.notes[pick.item.barRanges[0]].flatMap(\.keys).count : nil
                for (i, key) in keys.enumerated() {
                    let firstTry = pick.intro != nil || roll() < 0.6 + 0.37 * skill
                    let quicker = pick.pattern != nil && i >= (secondBar ?? keys.count) ? 0.7 : 1
                    let response = max(0.7, (4.4 - 3.3 * skill) * (0.7 + 0.6 * roll()) * quicker)
                    notes.append(AttemptResult(
                        itemID: key.id, lesson: lesson.id, level: lesson.level, wasIntro: pick.intro == key,
                        firstTry: firstTry, wrongPresses: firstTry ? 0 : 1, hints: firstTry ? .none : .wobble,
                        responseTime: response, inLine: i > 0 && pick.intro == nil && key != keys[i - 1]
                    ))
                    clock += response + 0.5
                }
                // level 2: his key-downs at a steady beat, a half now and then played short
                var measure: RhythmMeasure?
                if lesson.level == 2, pick.item.hasSameRhythmBars, !notes.contains(where: { !$0.firstTry }) {
                    var t = 0.0
                    let onsets = pick.item.notes.indices.map { i -> Double in
                        defer {
                            let short = pick.item.notes[i].value == .half && roll() < 0.5 * (1 - skill)
                            t += pick.item.gapBeats[i] * 0.9 * (0.85 + 0.3 * roll()) * (short ? 0.5 : 1)
                        }
                        return t
                    }
                    measure = RhythmJudge().measure(pick.item, onsets: onsets)
                }
                let screen = ScreenResult(screenID: pick.item.id, lesson: lesson.id, wasIntro: pick.intro != nil, notes: notes, size: pick.size,
                                          pattern: pick.pattern, secondBar: secondBar, rhythmMeasure: measure)
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
