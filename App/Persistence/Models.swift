import Foundation
import SwiftData

/// NoteCore's `MasteryState` and `NoteCoreConfig`, JSON-encoded. Normally one row.
/// A row that no longer decodes is left alone (never overwritten), so a bug can't
/// quietly wipe his progress.
@Model
final class MasteryRecord {
    var stateData: Data
    var configData: Data
    var updatedAt: Date

    init(stateData: Data, configData: Data, updatedAt: Date = Date()) {
        self.stateData = stateData
        self.configData = configData
        self.updatedAt = updatedAt
    }
}

/// One finished item. The fields the dashboard queries are plain properties; the
/// full `AttemptResult` is kept as JSON too.
@Model
final class AttemptRecord {
    var date: Date
    var itemID: String
    var unit: Int
    var wasIntro: Bool
    var firstTry: Bool
    var responseTime: Double
    /// `HintLevel.rawValue`
    var hints: Int
    var wrongPresses: Int
    var almostPresses: Int
    /// nil when the item has no rhythm or rhythm wasn't judged
    var rhythmOK: Bool?
    var resultData: Data

    init(
        date: Date, itemID: String, unit: Int, wasIntro: Bool, firstTry: Bool, responseTime: Double,
        hints: Int, wrongPresses: Int, almostPresses: Int, rhythmOK: Bool?, resultData: Data
    ) {
        self.date = date
        self.itemID = itemID
        self.unit = unit
        self.wasIntro = wasIntro
        self.firstTry = firstTry
        self.responseTime = responseTime
        self.hints = hints
        self.wrongPresses = wrongPresses
        self.almostPresses = almostPresses
        self.rhythmOK = rhythmOK
        self.resultData = resultData
    }
}

/// One session, including ones a parent ended early.
@Model
final class SessionRecord {
    var startedAt: Date
    var endedAt: Date
    var itemsPlayed: Int
    var firstTryCount: Int
    var activeDuration: Double
    var startUnit: Int
    var endUnit: Int
    /// `SessionSummary` as JSON
    var summaryData: Data

    init(
        startedAt: Date, endedAt: Date, itemsPlayed: Int, firstTryCount: Int, activeDuration: Double,
        startUnit: Int, endUnit: Int, summaryData: Data
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.itemsPlayed = itemsPlayed
        self.firstTryCount = firstTryCount
        self.activeDuration = activeDuration
        self.startUnit = startUnit
        self.endUnit = endUnit
        self.summaryData = summaryData
    }
}

/// The colour he picked for a muncher when it hatched. Munchers he met before colour
/// picking existed have no row and keep their hashed colour.
@Model
final class MuncherColorRecord {
    var itemID: String
    /// index into `MuncherLook.palette`
    var colorIndex: Int
    var pickedAt: Date

    init(itemID: String, colorIndex: Int, pickedAt: Date = Date()) {
        self.itemID = itemID
        self.colorIndex = colorIndex
        self.pickedAt = pickedAt
    }
}
