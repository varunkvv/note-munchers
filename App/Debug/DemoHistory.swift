#if DEBUG
import Foundation
import NoteCore

/// `-demoProgress YES`: three weeks of made-up practice through the real engine, so
/// munchers, the end screen and the dashboard trends have something to show.
/// About 18 items a day, slowly getting faster and more often right first try.
enum DemoHistory {
    @MainActor
    static func seed(into store: Store, days: Int = 21, seed: UInt64 = 42) -> MasteryEngine {
        var engine = MasteryEngine()
        var rng = SeededRandom(seed: seed)
        func roll() -> Double { Double(rng.next() >> 11) * 0x1p-53 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // leave today empty, so a demo session today is the newest
        for day in stride(from: days, through: 1, by: -1) {
            guard let start = calendar.date(byAdding: .day, value: -day, to: today)?.addingTimeInterval(17 * 3600) else { continue }
            let skill = 1 - Double(day) / Double(days)
            var summary = SessionSummary(startUnit: engine.unit.number)
            var clock = 0.0
            for _ in 0..<18 {
                let item = engine.pickNext(using: &rng)
                let intro = engine.needsIntro(item)
                let firstTry = intro || roll() < 0.6 + 0.37 * skill
                let response = max(0.7, (4.4 - 3.3 * skill) * (0.7 + 0.6 * roll()))
                let attempt = AttemptResult(
                    itemID: item.id, unit: engine.unit.number, wasIntro: intro, firstTry: firstTry,
                    wrongPresses: firstTry ? 0 : 1, hints: firstTry ? .none : .wobble, responseTime: response
                )
                let update = engine.record(attempt)
                clock += response + 2
                store.addAttempt(attempt, at: start.addingTimeInterval(clock), commit: false)
                summary.itemsPlayed += 1
                summary.firstTryCount += firstTry ? 1 : 0
                summary.attempts.append(attempt)
                summary.unlocked += update.unlocked
            }
            summary.activeDuration = clock
            summary.endUnit = engine.unit.number
            store.addSession(summary, startedAt: start, endedAt: start.addingTimeInterval(clock))
        }
        store.saveMastery(engine.state, config: engine.config)
        print("demo: seeded \(days) days, now unit \(engine.unit.number), \(engine.allProgress.count) items played")
        return engine
    }
}
#endif
