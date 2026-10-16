import Testing
@testable import NoteCore

/// Turns played lengths (seconds per note) into the key-down times and last key-up
/// the judge sees, starting at `start`.
func performance(_ lengths: [Double], start: Double = 10) -> (onsets: [Double], release: Double) {
    var onsets: [Double] = []
    var t = start
    for length in lengths {
        onsets.append(t)
        t += length
    }
    return (onsets, t)
}

@Suite struct RhythmJudgeTests {
    let judge = RhythmJudge()
    let rhythms = RhythmFixtures.roundOne

    func run(_ values: [NoteValue], _ lengths: [Double]) -> RhythmResult {
        let p = performance(lengths)
        return judge.judge(values, onsets: p.onsets, release: p.release)
    }

    @Test func exactAtAnyTempoPasses() {
        for values in rhythms {
            for beat in [0.3, 0.6, 1.2, 2.4] { // double speed, normal, half speed, quarter speed
                let result = run(values, values.map { $0.beats * beat })
                #expect(result.isOK, "\(RhythmFixtures.name(values)) at beat \(beat)")
                #expect(abs(result.beat - beat) < 1e-9)
            }
        }
    }

    @Test func samePhraseAtHalfAndDoubleSpeed() {
        let values: [NoteValue] = [.quarter, .quarter, .half, .quarter, .quarter, .half]
        let normal = values.map { $0.beats * 0.6 }
        #expect(run(values, normal.map { $0 * 2 }).isOK, "half speed")
        #expect(run(values, normal.map { $0 / 2 }).isOK, "double speed")
    }

    @Test func halfPlayedAsQuarterIsTooShort() {
        let values: [NoteValue] = [.half, .quarter, .quarter]
        // the plan's total-time formula would call this ok (0.67x). see context/notecore-design.md
        let result = run(values, [1, 1, 1])
        #expect(result.verdicts == [.tooShort, .ok, .ok])
        #expect(result.nudgeIndex == 0)
    }

    /// Every half in every fixture line, played as a quarter, comes back too short.
    @Test func everyCurriculumHalfShortenedIsTooShort() {
        for values in rhythms {
            for (i, value) in values.enumerated() where value == .half {
                var lengths = values.map { $0.beats * 0.6 }
                lengths[i] = NoteValue.quarter.beats * 0.6
                let result = run(values, lengths)
                #expect(result.verdicts[i] == .tooShort, "\(RhythmFixtures.name(values)) note \(i)")
                #expect(result.verdicts.enumerated().allSatisfy { $0.offset == i || $0.element == .ok }, "\(RhythmFixtures.name(values)) only note \(i) is off")
            }
        }
    }

    /// Every quarter next to an eighth, played as an eighth, comes back too short.
    @Test func everyCurriculumQuarterNextToAnEighthShortenedIsTooShort() {
        var checked = 0
        for values in rhythms {
            for (i, value) in values.enumerated() where value == .quarter {
                let neighbours = [i - 1, i + 1].filter { values.indices.contains($0) }.map { values[$0] }
                guard neighbours.contains(.eighth) else { continue }
                var lengths = values.map { $0.beats * 0.6 }
                lengths[i] = NoteValue.eighth.beats * 0.6
                #expect(run(values, lengths).verdicts[i] == .tooShort, "\(RhythmFixtures.name(values)) note \(i)")
                checked += 1
            }
        }
        #expect(checked >= 5)
    }

    /// Every quarter (not last) played as a half comes back too long.
    @Test func everyCurriculumQuarterPlayedAsHalfIsTooLong() {
        for values in rhythms {
            for (i, value) in values.enumerated().dropLast() where value == .quarter {
                var lengths = values.map { $0.beats * 0.6 }
                lengths[i] = NoteValue.half.beats * 0.6
                #expect(run(values, lengths).verdicts[i] == .tooLong, "\(RhythmFixtures.name(values)) note \(i)")
            }
        }
    }

    @Test func jitteryButRoughlyRightPasses() {
        var rng = SeededRandom(seed: 42)
        for trial in 0..<2000 {
            let values = rhythms[trial % rhythms.count]
            let beat = 0.4 + Double(rng.next() % 1000) / 1000 // 0.4s to 1.4s per quarter
            let lengths = values.map { value -> Double in
                let jitter = (Double(rng.next() % 1000) / 1000 - 0.5) * 0.4 // +-20%
                return value.beats * beat * (1 + jitter)
            }
            #expect(run(values, lengths).isOK, "\(RhythmFixtures.name(values)) trial \(trial)")
        }
    }

    @Test func slowingDownThroughThePhrasePasses() {
        let values: [NoteValue] = [.quarter, .quarter, .half, .quarter, .quarter, .half]
        let lengths = values.enumerated().map { i, v in v.beats * 0.6 * (1 + 0.05 * Double(i)) } // 25% slower by the end
        #expect(run(values, lengths).isOK)
    }

    @Test func lastNoteHeldForeverIsFine() {
        let values: [NoteValue] = [.quarter, .quarter, .half]
        let result = run(values, [0.6, 0.6, 30])
        #expect(result.isOK)
        #expect(abs(result.beat - 0.6) < 1e-9, "a long last hold doesn't stretch his beat")
    }

    @Test func lastNoteLiftedEarlyIsTooShort() {
        let result = run([.quarter, .quarter, .half], [0.6, 0.6, 0.6])
        #expect(result.verdicts == [.ok, .ok, .tooShort])
    }

    @Test func onePauseMidPhraseOnlyFlagsThatNote() {
        let values: [NoteValue] = [.quarter, .quarter, .quarter, .quarter, .half]
        let result = run(values, [0.6, 3.0, 0.6, 0.6, 1.2])
        #expect(result.verdicts == [.ok, .tooLong, .ok, .ok, .ok])
        #expect(result.nudgeIndex == 1)
    }

    @Test func eighthsVersusQuarters() {
        let values: [NoteValue] = [.eighth, .eighth, .quarter, .half]
        #expect(run(values, [0.3, 0.3, 0.6, 1.2]).isOK)
        // eighths played as quarters. half the notes are off by 2x, so it could also read as a
        // slow tempo with a short quarter and half. ties go to the faster tempo
        #expect(run(values, [0.6, 0.6, 0.6, 1.2]).verdicts == [.tooLong, .tooLong, .ok, .ok])
    }

    /// The main thing to catch: every note the same length never passes.
    @Test func everyNoteTheSameLengthNeverPasses() {
        for values in rhythms {
            for length in [0.3, 0.6, 1.0] {
                #expect(!run(values, values.map { _ in length }).isOK, "\(RhythmFixtures.name(values)) at \(length)s each")
            }
        }
    }

    @Test func settleTimeIsWhenTheHoldStopsMattering() {
        let values: [NoteValue] = [.quarter, .quarter, .half]
        let p = performance([0.6, 0.6, 0])
        let settle = judge.settleTime(values, onsets: p.onsets)
        #expect(abs(settle - (p.onsets[2] + 2 * 0.6 * 1.6)) < 1e-9, "half note at his beat x 1.6")
        let atSettle = judge.judge(values, onsets: p.onsets, release: settle)
        let muchLater = judge.judge(values, onsets: p.onsets, release: settle + 60)
        #expect(atSettle == muchLater)
        #expect(atSettle.isOK)
    }
}

enum RhythmFixtures {
    static let e = NoteValue.eighth, q = NoteValue.quarter, h = NoteValue.half

    /// The round-1 curriculum's rhythm lines (units 10-12), kept as fixed cases for the judge.
    static let roundOne: [[NoteValue]] = [
        [q, q, h], [h, q, q], [q, h, q], [q, q, h, q, q, h], [h, h, q, q, h], [q, q, q, q, h, h],
        [e, e, q, h], [q, e, e, q, q], [e, e, e, e, h], [h, e, e, q], [q, q, e, e, q], [e, e, q, e, e, q],
        [q, q, h, q, q, h], [q, q, q, q, q, q, h], [h, q, q, q, q, h], [e, e, e, e, h],
        [e, e, q, q, q, h, h], [q, e, e, h],
    ]

    static func name(_ values: [NoteValue]) -> String { values.map(\.rawValue).joined(separator: " ") }
}
