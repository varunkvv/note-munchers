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

/// Parent-facing names for items. The kid never sees these.
enum ItemLabel {
    static func text(_ id: ItemID) -> String {
        guard let item = Curriculum.standard.item(id) else { return id }
        let clef = item.clef == .treble ? "treble" : "bass"
        switch item.kind {
        case .note:
            return "\(item.notes[0].pitches[0].name) \(clef)"
        case .group:
            return item.notes.map { $0.pitches[0].name }.joined(separator: " ") + " (\(clef))"
        case .chord:
            return item.notes[0].pitches.map(\.name).joined(separator: "+")
        case .rhythm:
            let pitches = Set(item.notes.flatMap(\.pitches))
            let values = item.notes.map { $0.value?.rawValue ?? "" }
            if pitches.count == 1, let pitch = pitches.first {
                return "\(pitch.name): " + values.joined(separator: " ")
            }
            return zip(item.notes, values).map { "\($0.pitches[0].naturalLetter.name)\($1)" }.joined(separator: " ")
        }
    }
}

/// One specific thing for the parent to celebrate with him this week (relatedness:
/// noticing together). Picks the most concrete one: a finished unit, notes he met,
/// a note he finds a lot faster, more right first try, then simply showing up.
enum Celebration {
    static func suggest(engine: MasteryEngine, trends: Trends, records: [AttemptRecord], sessions: [SessionRecord], now: Date = Date()) -> String {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let decoder = JSONDecoder()
        let weekSessions = sessions.filter { $0.startedAt > weekAgo }
        let finished = weekSessions
            .compactMap { try? decoder.decode(SessionSummary.self, from: $0.summaryData) }
            .flatMap(\.completedUnits)
        if let unit = finished.max(), let title = engine.curriculum.unit(unit)?.title {
            return "He finished unit \(unit) (\(title.lowercased())) this week. Ask him to play you his favourite note from it."
        }

        // notes whose first counted try was this week
        var firstSeen: [ItemID: Date] = [:]
        for record in records where firstSeen[record.itemID] == nil {
            firstSeen[record.itemID] = record.date
        }
        let met = engine.curriculum.allItems.map(\.id).filter { (firstSeen[$0] ?? .distantPast) > weekAgo }
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
