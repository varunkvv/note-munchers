import Foundation
import Observation

/// Short-lived drawing effects on the staff: wobble (wrong key), sparkle (right key),
/// glow (rhythm nudge), follow (the note or rest sounding while the screen is played),
/// fade back and start here (a start over after a slip). The staff view animates only
/// while one is live, so the Canvas isn't redrawn every frame the rest of the time.
@MainActor @Observable
final class StaffEffects {
    enum Kind: Equatable {
        case wobble
        case sparkle
        case glow
        /// the note in `column` is sounding: a soft highlight to follow along
        case follow
        /// the rest at index `column` of the screen's rests (left to right) is sounding
        case followRest
        /// a note he had played (grey) going back to ink: the screen started over
        case fadeBack
        /// a soft light on the note to start from, after a start over
        case startHere
    }

    struct Effect: Identifiable, Equatable {
        let id = UUID()
        let kind: Kind
        let column: Int
        let start: Date
        let duration: Double

        func progress(at date: Date) -> Double {
            min(1, max(0, date.timeIntervalSince(start) / duration))
        }
    }

    private(set) var effects: [Effect] = []

    /// DEBUG demo runs stretch effects so screenshots can catch them mid-way.
    var timeScale = 1.0

    var isEmpty: Bool { effects.isEmpty }

    func add(_ kind: Kind, column: Int, duration: Double) {
        let effect = Effect(kind: kind, column: column, start: Date(), duration: duration * timeScale)
        effects.removeAll { $0.kind == kind && $0.column == column }
        effects.append(effect)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(effect.duration))
            self?.effects.removeAll { $0.id == effect.id }
        }
    }

    func clear() {
        effects.removeAll()
    }

    func active(_ kind: Kind, column: Int) -> Effect? {
        effects.last { $0.kind == kind && $0.column == column }
    }
}
