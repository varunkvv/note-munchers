/// Knowing a note vs it being automatic (plans/2026-10-16-drills-and-habit.md section 4).
///
/// The leitner box climbs on every first try, so box 5 can happen inside one session:
/// that measures knowing. Habit asks for more, from the times between notes on a screen
/// (MIDI can't see fingers, so note to key time is the proxy):
/// - in-line plays only: not a screen's first note (its time includes taking in a new
///   screen), not a repeat of the key before, not on a rhythm-judged screen
/// - the last `habitWindow` of them, `habitFirstTry` right first try (a wrong octave
///   isn't automatic, though the box holds)
/// - median under `habitMedian`, and steady: sd / mean under `habitCV`
/// - its first showing right first try in his last sessions on `habitDays` different days
///
/// Used for: weighting drill screens toward notes that aren't habit yet, finishing each
/// level's drill lesson, and the parent dashboard. Never the unlock gate: stalling unlocks
/// kills the surprise.
public struct HabitProgress: Hashable, Sendable {
    /// In-line plays in the window, up to `habitWindow`.
    public let samples: Int
    public let firstTries: Int
    public let median: Double?
    /// sd / mean of the window's times.
    public let steadiness: Double?
    /// His last different days (up to `habitDays`, newest first) whose first showing of
    /// it was right first try, before one that wasn't.
    public let cleanDays: Int
    public let isHabit: Bool
    /// 0...1: how far along, each part capped at 1 and averaged. 1 only when it's habit.
    public let fraction: Double
}

extension MasteryEngine {
    public func habit(_ key: NoteKey) -> HabitProgress {
        let s = stats(for: key)
        let window = s.inLine.suffix(config.habitWindow)
        let times = window.map(\.responseTime)
        let firstTries = window.filter(\.firstTry).count
        let middle = times.isEmpty ? nil : NoteCore.median(times)
        var steadiness: Double?
        if times.count >= 2 {
            let mean = times.reduce(0, +) / Double(times.count)
            let variance = times.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(times.count)
            steadiness = mean > 0 ? variance.squareRoot() / mean : nil
        }
        // the latest session of each day, newest day first
        var days: [Int] = []
        var clean = 0
        for first in s.sessionFirsts.reversed() where !days.contains(first.day) {
            days.append(first.day)
            guard first.clean, clean < config.habitDays else { break }
            clean += 1
        }
        let full = window.count >= config.habitWindow
        let isHabit = full && firstTries >= config.habitFirstTry && (middle ?? .infinity) < config.habitMedian
            && (steadiness ?? .infinity) < config.habitCV && clean >= config.habitDays
        let parts = [
            Double(window.count) / Double(max(1, config.habitWindow)),
            Double(firstTries) / Double(max(1, config.habitFirstTry)),
            middle.map { $0 < config.habitMedian ? 1 : config.habitMedian / $0 } ?? 0,
            steadiness.map { $0 < config.habitCV ? 1 : config.habitCV / $0 } ?? 0,
            Double(clean) / Double(max(1, config.habitDays)),
        ].map { min(1, max(0, $0)) }
        let fraction = isHabit ? 1 : min(0.99, parts.reduce(0, +) / Double(parts.count))
        return HabitProgress(samples: window.count, firstTries: firstTries, median: middle, steadiness: steadiness,
                             cleanDays: clean, isHabit: isHabit, fraction: fraction)
    }

    public func isHabit(_ key: NoteKey) -> Bool { habit(key).isHabit }

    /// A session starts on `day` (the app's day number; nil: a day of its own, for tests
    /// and demos). Counts toward the lesson's days.
    mutating func beginSession(day: Int?) {
        state.session += 1
        state.sessionDay = day ?? state.session
        state.lessonDays.insert(state.sessionDay)
    }

    /// A drill lesson finishes when every note in it is habit, or after
    /// `drillLessonMaxDays` days in it with the usual lesson rule met.
    var drillLessonReady: (habit: Bool, enoughDays: Bool) {
        (pool.allSatisfy(isHabit), state.lessonDays.count >= config.drillLessonMaxDays)
    }
}
