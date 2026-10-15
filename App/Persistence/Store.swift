import Foundation
import NoteCore
import SwiftData

/// Saves and loads his progress with SwiftData.
@MainActor
final class Store {
    let container: ModelContainer
    /// True when the real store couldn't open and we fell back to memory.
    /// The parent area says so, because nothing will be kept.
    private(set) var isTemporary: Bool
    private var context: ModelContext { container.mainContext }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    static let schema = Schema([MasteryRecord.self, AttemptRecord.self, SessionRecord.self, MuncherColorRecord.self])

    init(inMemory: Bool = false) {
        if !inMemory, let container = try? Self.openFile() {
            self.container = container
            isTemporary = false
            return
        }
        if !inMemory { print("store: couldn't open the store file, progress won't be kept") }
        // swiftlint:disable:next force_try
        container = try! ModelContainer(for: Self.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        isTemporary = !inMemory
    }

    /// Application Support/NoteMunchers/NoteMunchers.store. An explicit path so the
    /// unsandboxed mac app doesn't share SwiftData's default.store with other apps.
    private static func openFile() throws -> ModelContainer {
        let folder = URL.applicationSupportDirectory.appending(path: "NoteMunchers", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let config = ModelConfiguration(schema: schema, url: folder.appending(path: "NoteMunchers.store"))
        return try ModelContainer(for: schema, configurations: config)
    }

    // MARK: mastery

    /// The newest saved state that still decodes, and the parent's settings.
    func loadMastery() -> (MasteryState, ParentSettings)? {
        guard let record = newestReadableMastery() else { return nil }
        guard let state = try? decoder.decode(MasteryState.self, from: record.stateData) else { return nil }
        // older rows hold a whole NoteCoreConfig. its session-length keys decode fine
        // and the rest (NoteCore's tuning) is ignored on purpose
        let settings = (try? decoder.decode(ParentSettings.self, from: record.configData)) ?? ParentSettings()
        return (state, settings)
    }

    func saveMastery(_ state: MasteryState, settings: ParentSettings) {
        guard let stateData = try? encoder.encode(state), let configData = try? encoder.encode(settings) else { return }
        if let record = newestReadableMastery() {
            record.stateData = stateData
            record.configData = configData
            record.updatedAt = Date()
        } else {
            context.insert(MasteryRecord(stateData: stateData, configData: configData))
        }
        save()
    }

    private func newestReadableMastery() -> MasteryRecord? {
        let all = (try? context.fetch(FetchDescriptor<MasteryRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
        return all.first { (try? decoder.decode(MasteryState.self, from: $0.stateData)) != nil }
    }

    // MARK: history

    func addAttempt(_ attempt: AttemptResult, at date: Date = Date(), commit: Bool = true) {
        context.insert(AttemptRecord(
            date: date, itemID: attempt.itemID, unit: attempt.unit, wasIntro: attempt.wasIntro,
            firstTry: attempt.firstTry, responseTime: attempt.responseTime, hints: attempt.hints.rawValue,
            wrongPresses: attempt.wrongPresses, almostPresses: attempt.almostPresses,
            rhythmOK: attempt.rhythm?.isOK, resultData: (try? encoder.encode(attempt)) ?? Data()
        ))
        if commit { save() }
    }

    func addSession(_ summary: SessionSummary, startedAt: Date, endedAt: Date = Date()) {
        context.insert(SessionRecord(
            startedAt: startedAt, endedAt: endedAt, itemsPlayed: summary.itemsPlayed,
            firstTryCount: summary.firstTryCount, activeDuration: summary.activeDuration,
            startUnit: summary.startUnit, endUnit: summary.endUnit,
            summaryData: (try? encoder.encode(summary)) ?? Data()
        ))
        save()
    }

    /// Counted attempts (no intros), oldest first.
    func attempts(since: Date? = nil) -> [AttemptRecord] {
        var descriptor = FetchDescriptor<AttemptRecord>(sortBy: [SortDescriptor(\.date)])
        if let since {
            descriptor.predicate = #Predicate { $0.date >= since && !$0.wasIntro }
        } else {
            descriptor.predicate = #Predicate { !$0.wasIntro }
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Newest first.
    func sessions(limit: Int = 30) -> [SessionRecord] {
        var descriptor = FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: muncher colours

    func muncherColors() -> [String: Int] {
        let rows = (try? context.fetch(FetchDescriptor<MuncherColorRecord>(sortBy: [SortDescriptor(\.pickedAt)]))) ?? []
        return Dictionary(rows.map { ($0.itemID, $0.colorIndex) }, uniquingKeysWith: { _, newer in newer })
    }

    func saveMuncherColor(_ index: Int, for itemID: String) {
        context.insert(MuncherColorRecord(itemID: itemID, colorIndex: index))
        save()
    }

    func counts() -> (attempts: Int, sessions: Int) {
        let attempts = (try? context.fetchCount(FetchDescriptor<AttemptRecord>())) ?? 0
        let sessions = (try? context.fetchCount(FetchDescriptor<SessionRecord>())) ?? 0
        return (attempts, sessions)
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("store: save failed: \(error)")
        }
    }
}

/// What the parent sets: session length. Everything else in `NoteCoreConfig` is
/// NoteCore's tuning and always comes from `NoteCoreConfig.default`, so a tuning change
/// in a new build reaches an install that already saved settings.
struct ParentSettings: Codable, Equatable {
    var sessionMaxItems: Int?
    var sessionMaxDuration: Double?

    init(sessionMaxItems: Int? = nil, sessionMaxDuration: Double? = nil) {
        self.sessionMaxItems = sessionMaxItems
        self.sessionMaxDuration = sessionMaxDuration
    }

    init(_ config: NoteCoreConfig) {
        self.init(sessionMaxItems: config.sessionMaxItems, sessionMaxDuration: config.sessionMaxDuration)
    }

    /// NoteCore's defaults with the parent's choices on top.
    var config: NoteCoreConfig {
        var config = NoteCoreConfig.default
        if let sessionMaxItems { config.sessionMaxItems = sessionMaxItems }
        if let sessionMaxDuration { config.sessionMaxDuration = sessionMaxDuration }
        return config
    }
}
