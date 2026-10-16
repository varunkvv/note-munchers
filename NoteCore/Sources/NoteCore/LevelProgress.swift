/// How far he is in his level (plans/2026-10-16-progress-and-tunes.md): one stepping stone
/// per lesson, done stones full, the current one filling as the lesson goes.
///
/// The current lesson's fraction comes from the same parts as the lesson-done rule
/// (`isLessonDone`): his new notes met and at box 3, screens played in the lesson, and his
/// last notes right first try (and the rhythm track in rhythm lessons). It stays under 1
/// until the lesson is really done, so a stone only fills all the way when it's done.
///
/// It never goes backwards for him: the engine keeps the lesson's peak (like
/// `peakFluency`), so a bad day doesn't undo his path. A lesson starts from empty when he
/// enters it (a parent moving him counts as entering).
public struct LevelProgress: Hashable, Sendable {
    public let level: Int
    /// One per lesson of the level, in order: 1 done, 0 not started, in between the
    /// lesson he's in. A lesson a parent skipped over is 0.
    public let stones: [Double]
    /// The stone he's on (his current lesson), or nil when this isn't his level.
    public let current: Int?

    public init(level: Int, stones: [Double], current: Int?) {
        self.level = level
        self.stones = stones
        self.current = current
    }

    /// Lessons done plus the current lesson's fraction (0...stones.count).
    public var value: Double { stones.reduce(0, +) }

    public var doneCount: Int { stones.filter { $0 >= 1 }.count }
}

extension MasteryEngine {
    /// The highest a lesson's stone fills before the lesson is done.
    public static let lessonFractionCap = 0.9

    /// The current lesson's fraction right now, 0...`lessonFractionCap`. Can dip after
    /// misses (the window part): use `lessonProgress` for what he sees.
    public var liveLessonFraction: Double {
        let lesson = self.lesson
        let screens = min(1, Double(state.lessonScreens) / Double(max(1, config.lessonMinScreens)))
        let window = state.lessonRecent.suffix(config.lessonWindow)
        let needed = max(1, Double(config.lessonWindow) * config.lessonRate)
        let rightFirst = min(1, Double(window.filter(\.firstTry).count) / needed)
        var parts: [(value: Double, weight: Double)]
        let newKeys = lesson.newKeys
        if newKeys.isEmpty {
            // a practice lesson: every note is known already, so it's playing enough
            // screens and getting his last notes right
            parts = [(screens, 0.5), (rightFirst, 0.5)]
        } else {
            // a lesson with new notes: mostly meeting them and getting each to box 3
            let notes = newKeys.reduce(0.0) { $0 + noteFraction($1) } / Double(newKeys.count)
            parts = [(notes, 0.5), (screens, 0.2), (rightFirst, 0.3)]
        }
        if lesson.texture.isRhythm {
            let recent = state.rhythmRecent.suffix(config.solidWindow)
            let rhythm = min(1, Double(recent.filter { $0 }.count) / Double(max(1, config.rhythmSolidRequired)))
            parts = parts.map { ($0.value, $0.weight * 0.7) } + [(rhythm, 0.3)]
        }
        let total = parts.reduce(0.0) { $0 + $1.value * $1.weight } / parts.reduce(0.0) { $0 + $1.weight }
        return min(Self.lessonFractionCap, max(0, total))
    }

    /// What his current lesson's stone shows: the most it has been in this lesson.
    public var lessonProgress: Double { max(state.lessonPeak, liveLessonFraction) }

    /// His current level's path.
    public var levelProgress: LevelProgress { levelProgress(ofLevel: lesson.level) }

    /// Any level's path: done lessons full, his current lesson at `lessonProgress`.
    public func levelProgress(ofLevel number: Int) -> LevelProgress {
        let lessons = curriculum.level(number)?.lessons ?? []
        var current: Int?
        let stones = lessons.enumerated().map { i, lesson -> Double in
            if lesson.id == state.lesson {
                current = i
                return lessonProgress
            }
            return state.completedLessons.contains(lesson.id) ? 1 : 0
        }
        return LevelProgress(level: number, stones: stones, current: current)
    }

    /// A new note's part: 0 until he has met it, then up to 1 as it climbs to box 3 (and,
    /// in a paced lesson, as he plays it toward `lessonMinNewPlays`, half each).
    private func noteFraction(_ key: NoteKey) -> Double {
        guard isUnlocked(key), state.introduced.contains(key.id) || stats(for: key).attempts > 0 else { return 0 }
        let box = Double(stats(for: key).box)
        let climbed = min(1, max(0, (box - 1) / Double(max(1, config.gateMinBox - 1))))
        guard lesson.paced else { return 0.3 + 0.7 * climbed }
        let played = min(1, Double(lessonPlays(key)) / Double(max(1, config.lessonMinNewPlays)))
        return 0.3 + 0.35 * climbed + 0.35 * played
    }
}
