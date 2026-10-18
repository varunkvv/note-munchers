import Foundation
import NoteCore

/// Per-item accuracy and speed over time, from the saved attempts. Only his own
/// trajectory: this week against last week, and a point per day.
struct Trends {
    struct Window {
        var median: Double?
        var firstTryRate: Double?
        var count = 0
    }

    struct Day: Identifiable {
        let date: Date
        let median: Double
        let firstTryRate: Double
        let count: Int
        var id: Date { date }
    }

    struct Item: Identifiable {
        let id: ItemID
        let thisWeek: Window
        let lastWeek: Window
        let days: [Day]
    }

    let items: [ItemID: Item]
    let thisWeek: Window
    let lastWeek: Window

    struct Sample {
        let date: Date
        let itemID: ItemID
        let firstTry: Bool
        let responseTime: Double
    }

    init(records: [AttemptRecord], now: Date = Date()) {
        self.init(samples: records.map { Sample(date: $0.date, itemID: $0.itemID, firstTry: $0.firstTry, responseTime: $0.responseTime) }, now: now)
    }

    init(samples: [Sample], now: Date = Date()) {
        let calendar = Calendar.current
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 86_400)
        func window(_ list: [Sample]) -> Window {
            guard !list.isEmpty else { return Window() }
            return Window(
                median: Self.median(list.map(\.responseTime)),
                firstTryRate: Double(list.filter(\.firstTry).count) / Double(list.count),
                count: list.count
            )
        }
        thisWeek = window(samples.filter { $0.date > weekAgo })
        lastWeek = window(samples.filter { $0.date > twoWeeksAgo && $0.date <= weekAgo })
        var items: [ItemID: Item] = [:]
        for (id, list) in Dictionary(grouping: samples, by: \.itemID) {
            let byDay = Dictionary(grouping: list) { calendar.startOfDay(for: $0.date) }
            let days = byDay.map { date, day in
                Day(date: date, median: Self.median(day.map(\.responseTime)) ?? 0,
                    firstTryRate: Double(day.filter(\.firstTry).count) / Double(day.count), count: day.count)
            }.sorted { $0.date < $1.date }
            items[id] = Item(
                id: id,
                thisWeek: window(list.filter { $0.date > weekAgo }),
                lastWeek: window(list.filter { $0.date > twoWeeksAgo && $0.date <= weekAgo }),
                days: days
            )
        }
        self.items = items
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// "0.8 s faster than last week" etc. nil when there's nothing to compare.
    static func speedChange(_ item: Item) -> (text: String, better: Bool?)? {
        guard let now = item.thisWeek.median else { return nil }
        guard let before = item.lastWeek.median else { return ("new this week", nil) }
        let diff = before - now
        if abs(diff) < 0.15 { return ("same speed as last week", nil) }
        let amount = String(format: "%.1f s", abs(diff))
        return diff > 0 ? ("\(amount) faster than last week", true) : ("\(amount) slower than last week", false)
    }
}

/// Parent-facing names for notes. The kid never sees these.
enum ItemLabel {
    /// "G4 treble", "F#3 bass". Round-1 item ids that aren't notes come back as they are.
    static func text(_ id: ItemID) -> String {
        guard let key = NoteKey(id: id) else { return id }
        return "\(key.pitch.name) \(key.clef.rawValue)"
    }
}

/// One specific thing for the parent to celebrate with him this week (relatedness:
/// noticing together). Picks the most concrete one: a finished lesson, notes he met,
/// a note he finds a lot faster, more right first try, then simply showing up.
enum Celebration {
    static func suggest(engine: MasteryEngine, trends: Trends, records: [AttemptRecord], sessions: [SessionRecord], now: Date = Date()) -> String {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let decoder = JSONDecoder()
        let weekSessions = sessions.filter { $0.startedAt > weekAgo }
        let finished = weekSessions
            .compactMap { try? decoder.decode(SessionSummary.self, from: $0.summaryData) }
            .flatMap(\.completedLessons)
        if let id = finished.max(by: { (engine.curriculum.index(of: $0) ?? 0) < (engine.curriculum.index(of: $1) ?? 0) }),
           let lesson = engine.curriculum.lesson(id) {
            return "He finished lesson \(id) (\(lesson.title.lowercased())) this week. Ask him to play you his favourite note from it."
        }

        // notes whose first counted try was this week
        var firstSeen: [ItemID: Date] = [:]
        for record in records where firstSeen[record.itemID] == nil {
            firstSeen[record.itemID] = record.date
        }
        let met = engine.curriculum.allKeys.map(\.id).filter { (firstSeen[$0] ?? .distantPast) > weekAgo }
        if !met.isEmpty {
            let names = met.prefix(3).map(ItemLabel.text)
            let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!
            return "He learned \(list) this week. Ask him to show you where \(met.count == 1 ? "it lives" : "they live") on the piano."
        }

        let faster = trends.items.values.compactMap { item -> (ItemID, Double)? in
            guard let now = item.thisWeek.median, let before = item.lastWeek.median, before - now >= 0.4 else { return nil }
            return (item.id, before - now)
        }.max { $0.1 < $1.1 }
        if let (id, gain) = faster {
            return "He finds \(ItemLabel.text(id)) \(String(format: "%.1f", gain)) s faster than last week. Ask him to show you how quickly he can find it."
        }

        if let rate = trends.thisWeek.firstTryRate, let before = trends.lastWeek.firstTryRate, rate - before >= 0.1 {
            return "He got more notes right on the first try this week (\(ParentView.percent(rate)), up from \(ParentView.percent(before))). Tell him you noticed how carefully he reads."
        }

        let days = Set(weekSessions.map { Calendar.current.startOfDay(for: $0.startedAt) }).count
        if days > 0 {
            return "He came back to the piano on \(days) \(days == 1 ? "day" : "days") this week. Tell him you noticed."
        }
        return "No practice this week, and that's fine. Nothing in the app shows a missed day."
    }
}

/// Pattern screens (two bars, bar 2 made from bar 1) and level 2's silent rhythm measure,
/// from the saved sessions (plans/2026-10-17-reset-and-repetition.md section 2): does bar 2
/// come faster than bar 1, and does he already hold halves longer than quarters.
struct PatternStats {
    /// Times and right-first-try per bar, per note. Bar 1 leaves out the screen's first
    /// note (its time includes taking in a new screen).
    struct Bars {
        var screens = 0
        var bar1: [Double] = []
        var bar2: [Double] = []
        var bar1Right = 0
        var bar2Right = 0

        var bar1Median: Double? { Trends.median(bar1) }
        var bar2Median: Double? { Trends.median(bar2) }
        var bar1Rate: Double? { bar1.isEmpty ? nil : Double(bar1Right) / Double(bar1.count) }
        var bar2Rate: Double? { bar2.isEmpty ? nil : Double(bar2Right) / Double(bar2.count) }

        mutating func add(_ screen: ScreenResult, split: Int) {
            screens += 1
            for note in screen.notes[1..<split] {
                bar1.append(note.responseTime)
                bar1Right += note.firstTry ? 1 : 0
            }
            for note in screen.notes[split...] {
                bar2.append(note.responseTime)
                bar2Right += note.firstTry ? 1 : 0
            }
        }
    }

    var shapes: [PatternShape: Bars] = [:]
    /// Every pattern screen.
    var patterns = Bars()
    /// Other two-bar screens, to compare against: bar 2 there is just more reading.
    var others = Bars()
    /// Level 2 screens whose bars share a rhythm, played clean.
    var measured = 0
    var halvesCompared = 0
    var halvesLonger = 0
    var barsCompared = 0
    var barsMatch = 0

    init(summaries: [SessionSummary]) {
        for screen in summaries.flatMap(\.screens) where screen.reason != .again && !screen.wasIntro && !screen.wasLessonIntro {
            if let measure = screen.rhythmMeasure {
                measured += 1
                if let longer = measure.halvesLonger {
                    halvesCompared += 1
                    halvesLonger += longer ? 1 : 0
                }
                if let match = measure.barsMatch {
                    barsCompared += 1
                    barsMatch += match ? 1 : 0
                }
            }
            // rhythm lessons give every note the screen's reading time: no bar to compare
            guard let split = screen.secondBar, split > 1, split < screen.notes.count,
                  Curriculum.standard.lesson(screen.lesson)?.texture.isRhythm == false else { continue }
            if let shape = screen.pattern {
                shapes[shape, default: Bars()].add(screen, split: split)
                patterns.add(screen, split: split)
            } else if [.normal, .stretch].contains(screen.reason) {
                others.add(screen, split: split)
            }
        }
    }

    /// Parent-facing names.
    static func name(_ shape: PatternShape) -> String {
        switch shape {
        case .frame: "same rhythm, new notes"
        case .moved: "moved a step"
        case .answer: "same, new last note"
        case .twin: "the same again"
        case .oneNote: "one note a bar"
        case .newRhythm: "same notes, new rhythm"
        }
    }

    /// "1.4 s / 0.9 s"
    static func times(_ bars: Bars) -> String {
        let one = bars.bar1Median.map { String(format: "%.1f s", $0) } ?? "-"
        let two = bars.bar2Median.map { String(format: "%.1f s", $0) } ?? "-"
        return "\(one) / \(two)"
    }
}
