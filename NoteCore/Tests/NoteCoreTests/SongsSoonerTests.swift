import Testing
@testable import NoteCore

/// Songs sooner (plans/2026-10-16-progress-and-tunes.md, section 3): any G plus 2 notes
/// makes a song, and level 1 songs can end B-G or D-G, so they don't need A.
@Suite struct SongsSoonerTests {
    static let letters: [Letter] = [.a, .b, .c, .d]

    /// Every G position set with G and 2 or more others, in one clef.
    static func sets(_ clef: Clef) -> [[Pitch]] {
        let range = MasteryEngine.songRange(level: 1, clef: clef)
        let others = Array(range.dropFirst())
        var out: [[Pitch]] = []
        for mask in 1..<(1 << others.count) {
            let pick = others.indices.filter { mask & (1 << $0) != 0 }.map { others[$0] }
            if pick.count >= 2 { out.append([range[0]] + pick) }
        }
        return out
    }

    /// The meter `songRequest` would pick: 3/4 only when the hand can end from a V7 bar.
    static func meter(_ wanted: Meter, _ set: [Pitch]) -> Meter {
        set.contains { $0.letter == .a || $0.letter == .d } ? wanted : .fourFour
    }

    /// Level 1, every set, both clefs, both meters: a real song (or a fallback that
    /// keeps the rules), only his notes, ending on G.
    @Test func everySetWithGMakesASong() {
        var fallbacks: [String: Int] = [:]
        for clef in Clef.allCases {
            for set in Self.sets(clef) {
                for wanted in Meter.allCases {
                    let meter = Self.meter(wanted, set)
                    let request = SongRequest(level: 1, meter: meter, hands: [clef, clef], treble: clef == .treble ? set : [],
                                              bass: clef == .bass ? set : [], bars: 4)
                    for seed in UInt64(0)..<12 {
                        let song = SongGenerator.song(request, seed: seed)
                        let broken = SongGenerator.violations(song, notes: request.notes)
                            .filter { !(song.isFallback && $0.hasSuffix("is never used")) }
                        #expect(broken.isEmpty, "\(set.map(\.name)) \(meter.rawValue) seed \(seed): \(broken)")
                        #expect(song.notes.last!.pitches.contains { $0.letter == .g })
                        if song.isFallback { fallbacks[set.map(\.name).joined(separator: " "), default: 0] += 1 }
                    }
                }
            }
        }
        print("songs sooner: fallbacks of 24 per set \(fallbacks.sorted { $0.key < $1.key })")
        // the sets he can have in 1.3 and 1.4 without A all make real songs
        for set in ["G4 B4 C5", "G4 B4 D5", "G4 C5 D5", "G4 B4 C5 D5"] {
            #expect((fallbacks[set] ?? 0) <= 4, "\(set): \(fallbacks[set] ?? 0) of 24 fell back")
        }
    }

    /// The new endings show up: B-G and D-G in level 1, not only A-G.
    @Test func levelOneEndsFromABOrD() {
        let set = MasteryEngine.songRange(level: 1, clef: .treble)
        var approaches = Set<Letter>()
        for seed in UInt64(0)..<150 {
            let request = SongRequest(level: 1, meter: seed.isMultiple(of: 2) ? .fourFour : .threeFour, hands: [.treble, .treble],
                                      treble: set, bars: 4)
            let song = SongGenerator.song(request, seed: seed)
            let line = song.notes.map { $0.pitches[0] }
            if let approach = line.dropLast().last(where: { $0.letter != .g }), let letter = approach.letter { approaches.insert(letter) }
        }
        #expect(approaches.isSubset(of: [.a, .b, .d]))
        #expect(approaches.contains(.a), "A-G is still the usual ending: \(approaches)")
        #expect(approaches.count >= 2, "\(approaches)")
    }

    /// A B-G or D-G ending is fine in level 1, any other skip into the last G isn't, and
    /// a B-G skip in the middle of a level 1 song (with A in his notes) still isn't.
    @Test func onlyTheLastMoveFalls() {
        let set = MasteryEngine.songRange(level: 1, clef: .treble)
        let b = Pitch("B4")!, d = Pitch("D5")!, g = Pitch("G4")!, c = Pitch("C5")!
        #expect(SongGenerator.moveAllowed(from: b, to: g, level: 1, set: set, final: true))
        #expect(SongGenerator.moveAllowed(from: d, to: g, level: 1, set: set, final: true))
        #expect(!SongGenerator.moveAllowed(from: c, to: g, level: 1, set: set, final: true))
        #expect(!SongGenerator.moveAllowed(from: b, to: g, level: 1, set: set))
        #expect(!SongGenerator.moveAllowed(from: g, to: b, level: 1, set: set, final: true), "rising isn't an ending")
        #expect(SongGenerator.approachesFinal(b, level: 1, set: set))
        #expect(!SongGenerator.approachesFinal(b, level: 2, set: set), "level 2 with an A keeps its endings")
        #expect(SongGenerator.approachesFinal(b, level: 2, set: [g, b, c]))
    }

    /// The fallback never plays a note he doesn't have (it used to borrow A).
    @Test func theFallbackStaysOnHisNotes() {
        for level in 1...2 {
            for set in Self.sets(.treble) + Self.sets(.bass) where !set.contains(where: { $0.letter == .a }) {
                let clef: Clef = set[0].octave >= 4 ? .treble : .bass
                for meter in Meter.allCases {
                    let request = SongRequest(level: level, meter: meter, hands: [clef, clef], treble: clef == .treble ? set : [],
                                              bass: clef == .bass ? set : [], bars: level == 1 ? 4 : 8)
                    let song = SongGenerator.fallback(request, title: "Test", seed: 1)
                    let broken = SongGenerator.violations(song, notes: request.notes).filter { !$0.hasSuffix("is never used") }
                    #expect(broken.isEmpty, "level \(level) \(set.map(\.name)) \(meter.rawValue): \(broken)")
                }
            }
        }
    }
}
