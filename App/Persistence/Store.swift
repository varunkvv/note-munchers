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

    static let schema = Schema([MasteryRecord.self, AttemptRecord.self, SessionRecord.self])

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

    /// The newest saved state that still decodes.
    func loadMastery() -> (MasteryState, NoteCoreConfig)? {
        guard let record = newestReadableMastery() else { return nil }
        guard let state = try? decoder.decode(MasteryState.self, from: record.stateData) else { return nil }
        let config = (try? decoder.decode(NoteCoreConfig.self, from: record.configData)) ?? NoteCoreConfig()
        return (state, config)
    }

    func saveMastery(_ state: MasteryState, config: NoteCoreConfig) {
        guard let stateData = try? encoder.encode(state), let configData = try? encoder.encode(config) else { return }
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

    func addAttempt(_ attempt: AttemptResult, at date: Date = Date()) {
        context.insert(AttemptRecord(
            date: date, itemID: attempt.itemID, unit: attempt.unit, wasIntro: attempt.wasIntro,
            firstTry: attempt.firstTry, responseTime: attempt.responseTime, hints: attempt.hints.rawValue,
            wrongPresses: attempt.wrongPresses, almostPresses: attempt.almostPresses,
            rhythmOK: attempt.rhythm?.isOK, resultData: (try? encoder.encode(attempt)) ?? Data()
        ))
        save()
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
