import Testing
@testable import NoteCore

/// Song time's generator (artifacts/free-play/composer.md, "tests").
@Suite struct SongTests {
    /// G position in both clefs, or level 3's upper five (C to G with the F#).
    static func request(level: Int, meter: Meter, hands: [Clef], treble: [Pitch]? = nil, bass: [Pitch]? = nil,
                        bars: Int? = nil, recent: [String] = []) -> SongRequest {
        let range = { (clef: Clef) in Array(MasteryEngine.songRange(level: level, clef: clef).suffix(5)) }
        return SongRequest(level: level, meter: meter, hands: hands, treble: treble ?? range(.treble), bass: bass ?? range(.bass),
                           bars: bars ?? (level == 1 ? 4 : 8), recent: recent)
    }

    /// Songs for many seeds at once (a song takes a few ms, so the big runs go wide).
    static func songs(_ requests: [(SongRequest, UInt64)]) async -> [Song] {
        await withTaskGroup(of: (Int, [Song]).self) { group in
            let chunk = max(1, requests.count / 16 + 1)
            for start in stride(from: 0, to: requests.count, by: chunk) {
                let part = Array(requests[start..<min(start + chunk, requests.count)])
                group.addTask { (start, part.map { SongGenerator.song($0.0, seed: $0.1) }) }
            }
            var out: [(Int, [Song])] = []
            for await result in group { out.append(result) }
            return out.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }

    static func p(_ name: String) -> Pitch { Pitch(name)! }

    /// `"B4/q A4/q G4+B4/h"` on one staff.
    static func bar(_ clef: Clef, _ chords: [Chord], _ notes: String) -> SongBar {
        SongBar(notes.split(separator: " ").map { token in
            let parts = token.split(separator: "/")
            let pitches = parts[0].split(separator: "+").map { Pitch(String($0))! }
            return WrittenNote(clef, pitches, NoteValue(rawValue: String(parts[1]))!)
        }, chords: chords)
    }

    static let gPositionTreble = ["G4", "A4", "B4", "C5", "D5"].map(p)

    // MARK: same seed, different seeds

    @Test func sameSeedSameSong() {
        for level in 1...5 {
            for meter in Meter.allCases {
                let r = Self.request(level: level, meter: meter, hands: level == 1 ? [.bass, .bass] : [.treble, .bass])
                for seed: UInt64 in [0, 7, 99] {
                    let a = SongGenerator.song(r, seed: seed), b = SongGenerator.song(r, seed: seed)
                    #expect(a == b)
                    #expect(a.signature == b.signature)
                    #expect(a.seed == seed)
                }
            }
        }
    }

    /// 1000 seeds, 8 bar songs (half in each meter): 95%+ different songs.
    @Test func eightBarSongsAreDistinct() async {
        let requests = (UInt64(0)..<1000).map { seed in
            (Self.request(level: 2, meter: seed.isMultiple(of: 2) ? .fourFour : .threeFour, hands: [.treble, .bass]), seed)
        }
        let songs = await Self.songs(requests)
        let distinct = Set(songs.map(\.signature)).count
        print("songs: 1000 level 2 seeds -> \(distinct) distinct")
        #expect(distinct >= 950)
    }

    /// 4 bars, steps only, 3-5 notes can't make 950 different songs (3/4 with G A B is
    /// about 20 in all). What he needs is never a song from his last 20, and that holds
    /// wherever there are that many.
    @Test(arguments: [Meter.fourFour, .threeFour])
    func levelOneSongsDontRepeatWithinTwenty(meter: Meter) {
        for clef in Clef.allCases {
            var recent: [String] = []
            var songs: [String] = []
            for seed in UInt64(100)..<130 {
                let r = Self.request(level: 1, meter: meter, hands: [clef, clef], recent: recent)
                let song = SongGenerator.song(r, seed: seed)
                #expect(!song.isFallback)
                songs.append(song.signature)
                recent = Array((recent + [song.signature]).suffix(20))
            }
            for i in songs.indices {
                #expect(!songs[max(0, i - 20)..<i].contains(songs[i]), "\(meter.rawValue) \(clef) song \(i) repeats")
            }
        }
    }

    @Test func levelOneVariety() async {
        // for the record: how many different songs 120 seeds give at level 1
        for meter in Meter.allCases {
            let full = await Self.songs((UInt64(0)..<120).map { (Self.request(level: 1, meter: meter, hands: [.treble, .treble]), $0) })
            let three = await Self.songs((UInt64(0)..<120).map {
                (Self.request(level: 1, meter: meter, hands: [.treble, .treble], treble: ["G4", "A4", "B4"].map(Self.p)), $0)
            })
            print("songs: level 1 \(meter.rawValue), 120 seeds: G-D \(Set(full.map(\.signature)).count) distinct, G A B \(Set(three.map(\.signature)).count)")
            // 3/4 is 4 bars of about 8 notes that use all five keys by step: about 20 songs exist
            #expect(Set(full.map(\.signature)).count >= (meter == .fourFour ? 70 : 15))
        }
    }

    /// When every song he could get is in his last 20, he gets the one he heard longest ago.
    @Test func aTinySetCyclesThroughTheOldest() {
        var recent: [String] = []
        let three = ["G2", "A2", "B2"].map(Self.p)
        var seen: [String] = []
        for seed in UInt64(0)..<60 {
            let song = SongGenerator.song(Self.request(level: 1, meter: .threeFour, hands: [.bass, .bass], bass: three, recent: recent), seed: seed)
            #expect(!song.isFallback)
            if let at = recent.firstIndex(of: song.signature) { #expect(at <= 1, "a recent song came back before older ones") }
            seen.append(song.signature)
            recent = Array((recent + [song.signature]).suffix(20))
        }
        print("songs: level 1 3/4 G A B bass has \(Set(seen).count) songs")
    }

    // MARK: the hard rules, everywhere

    /// Seeds x level x meter x hands x his notes: every song keeps every hard rule, nothing
    /// he hasn't learned (eighths before 5, two at once before 4, F# before 3), and the
    /// fallback almost never.
    @Test(arguments: 1...5)
    func hardRulesHold(level: Int) async {
        var requests: [(SongRequest, UInt64)] = []
        let plans: [[Clef]] = level == 1 ? [[.treble, .treble], [.bass, .bass]] : [[.treble, .bass], [.bass, .treble], [.treble, .treble], [.bass, .bass]]
        var sets: [([Pitch], [Pitch])] = [(Array(MasteryEngine.songRange(level: level, clef: .treble).suffix(5)),
                                          Array(MasteryEngine.songRange(level: level, clef: .bass).suffix(5)))]
        switch level {
        case 1: sets += [(["G4", "A4", "B4"].map(Self.p), ["G2", "A2", "B2"].map(Self.p)),
                         (["G4", "A4", "B4", "D5"].map(Self.p), ["G2", "A2", "C3", "D3"].map(Self.p))]
        case 3: sets += [(Array(MasteryEngine.songRange(level: 3, clef: .treble).prefix(5)), Array(MasteryEngine.songRange(level: 3, clef: .bass).prefix(5)))]
        default: sets += [(["G4", "A4", "B4", "C5"].map(Self.p), ["G2", "A2", "B2", "D3"].map(Self.p))]
        }
        for meter in Meter.allCases {
            for hands in plans {
                for (treble, bass) in sets {
                    for seed in UInt64(0)..<12 {
                        requests.append((Self.request(level: level, meter: meter, hands: hands, treble: treble, bass: bass), seed * 7919 + UInt64(level)))
                    }
                }
            }
        }
        let songs = await Self.songs(requests)
        var fallbacks = 0
        for (song, (request, _)) in zip(songs, requests) {
            if song.isFallback { fallbacks += 1; continue }
            let broken = SongGenerator.violations(song, notes: request.notes)
            #expect(broken.isEmpty, "\(song.signature): \(broken)")
            let values = Set(song.notes.map(\.value))
            #expect(level >= 5 || !values.contains(.eighth))
            #expect(level >= 4 || !song.notes.contains(where: \.isChord))
            #expect(level >= 3 || song.notes.allSatisfy { $0.pitches.allSatisfy(\.isWhiteKey) })
            #expect(song.bars.count == request.bars)
            #expect(song.keySignature == (level >= 3 ? .gMajor : .none))
            for bar in song.bars { #expect(bar.notes.reduce(0) { $0 + $1.span } == Double(request.meter.beats)) }
        }
        print("songs: level \(level), \(songs.count) songs, \(fallbacks) fallbacks")
        #expect(Double(fallbacks) < Double(songs.count) * 0.001 + 1e-9)
        if level == 4 { #expect(songs.contains { $0.notes.contains(where: \.isChord) }) }
        if level == 5 { #expect(songs.contains { $0.notes.contains { $0.value == .eighth } }) }
        if level == 3 { #expect(songs.contains { $0.notes.contains { !$0.pitches[0].isWhiteKey } }) }
    }

    /// The fallback keeps every rule but "uses every note" and "not a recent song".
    @Test func fallbackIsASong() {
        for level in 1...5 {
            for meter in Meter.allCases {
                for hands: [Clef] in [[.treble, .treble], [.bass, .bass], [.treble, .bass]] where level > 1 || hands[0] == hands[1] {
                    let r = Self.request(level: level, meter: meter, hands: hands)
                    let song = SongGenerator.fallback(r, title: "Test", seed: 1)
                    let broken = SongGenerator.violations(song, notes: r.notes).filter { !$0.hasSuffix("is never used") }
                    #expect(broken.isEmpty, "level \(level) \(meter.rawValue) \(hands): \(broken)")
                }
            }
        }
        // only G and A
        let ga = Self.request(level: 1, meter: .fourFour, hands: [.treble, .treble], treble: ["G4", "A4"].map(Self.p))
        #expect(SongGenerator.violations(SongGenerator.fallback(ga, title: "Test", seed: 1), notes: ga.notes).isEmpty)
    }

    // MARK: songs everyone knows

    static let odeToJoy = Song(seed: 0, level: 1, meter: .fourFour, keySignature: .none, form: .abac, bars: [
        bar(.treble, [.I], "B4/q B4/q C5/q D5/q"), bar(.treble, [.V7], "D5/q C5/q B4/q A4/q"),
        bar(.treble, [.I], "G4/q G4/q A4/q B4/q"), bar(.treble, [.I, .V], "B4/q A4/q A4/h"),
        bar(.treble, [.I], "B4/q B4/q C5/q D5/q"), bar(.treble, [.V7], "D5/q C5/q B4/q A4/q"),
        bar(.treble, [.I], "G4/q G4/q A4/q B4/q"), bar(.treble, [.V7, .I], "A4/q G4/q G4/h"),
    ], title: "Ode to Joy", layout: .treble)

    static let mary = Song(seed: 0, level: 2, meter: .fourFour, keySignature: .none, form: .abac, bars: [
        bar(.treble, [.I], "B4/q A4/q G4/q A4/q"), bar(.treble, [.I], "B4/q B4/q B4/h"),
        bar(.treble, [.V], "A4/q A4/q A4/h"), bar(.treble, [.I], "B4/q D5/q D5/h"),
        bar(.treble, [.I], "B4/q A4/q G4/q A4/q"), bar(.treble, [.I], "B4/q B4/q B4/q B4/q"),
        bar(.treble, [.V], "A4/q A4/q B4/q A4/q"), bar(.treble, [.I], "G4/w"),
    ], title: "Mary Had a Little Lamb", layout: .treble)

    @Test func odeToJoyAndMaryPass() {
        #expect(SongGenerator.violations(Self.odeToJoy, notes: { _ in Self.gPositionTreble }) == [])
        #expect(SongGenerator.violations(Self.mary, notes: { _ in ["G4", "A4", "B4", "D5"].map(Self.p) }) == [])
    }

    @Test func endsOnAFails() {
        let half = Song(seed: 0, level: 1, meter: .fourFour, keySignature: .none, form: .ab, bars: Array(Self.odeToJoy.bars.prefix(4)),
                        title: "", layout: .treble)
        let broken = SongGenerator.violations(half, notes: { _ in Self.gPositionTreble })
        #expect(broken.contains("ends on A4"), "\(broken)")
    }

    @Test func startsOnCFails() {
        var bars = Self.mary.bars
        bars[0] = Self.bar(.treble, [.I], "C5/q A4/q G4/q A4/q")
        let song = Song(seed: 0, level: 2, meter: .fourFour, keySignature: .none, form: .abac, bars: bars, title: "", layout: .treble)
        let broken = SongGenerator.violations(song, notes: { _ in Self.gPositionTreble })
        #expect(broken.contains("starts on C5"), "\(broken)")
    }

    @Test func randomWalksFail() {
        let chords: [[Chord]] = [[.I], [.IV], [.I], [.V], [.I], [.IV], [.V7], [.I]]
        for seed in UInt64(0)..<20 {
            var rng = SeededRandom(seed: seed)
            var i = 2
            let bars = chords.map { chord -> SongBar in
                SongBar((0..<4).map { _ in
                    i = min(4, max(0, i + Int(unitInterval(&rng) * 5) - 2))
                    return WrittenNote(.treble, [Self.gPositionTreble[i]], .quarter)
                }, chords: chord)
            }
            let song = Song(seed: seed, level: 2, meter: .fourFour, keySignature: .none, form: .abac, bars: bars, title: "", layout: .treble)
            #expect(!SongGenerator.violations(song, notes: { _ in Self.gPositionTreble }).isEmpty)
        }
    }

    // MARK: one song, pinned

    @Test func snapshotSeed42LevelTwo() {
        let song = SongGenerator.song(Self.request(level: 2, meter: .fourFour, hands: [.treble, .bass]), seed: 42)
        #expect(song.title == SongTests.snapshot.title)
        #expect(song.form == SongTests.snapshot.form)
        #expect(song.bars.map(\.chords) == SongTests.snapshot.chords)
        #expect(song.signature == SongTests.snapshot.signature)
    }

    /// Recorded 2026-10-16. A change here means every seed makes a different song now:
    /// fine if the generator was meant to change, but say so.
    static let snapshot = (
        title: "Green Bee Stomp", form: SongForm.abac,
        chords: [[Chord.I], [.I], [.IV], [.V], [.I], [.I], [.IV, .V], [.I]],
        signature: "treble:G4/h-A4/q-G4/q treble:G4/h-A4/q-B4/q treble:G4/q-C5/q-B4/h treble:A4/h-D5/h "
            + "bass:G2/h-A2/q-G2/q bass:G2/h-A2/q-B2/q bass:C3/h-D3/q-A2/q bass:B2/q-A2/q-G2/h 4/4"
    )

    // MARK: pages

    @Test func levelOneIsOnePageOfTwoSystems() {
        for meter in Meter.allCases {
            let song = SongGenerator.song(Self.request(level: 1, meter: meter, hands: [.treble, .treble]), seed: 3)
            let pages = song.pages
            #expect(pages.count == 1)
            #expect(pages[0].systems.count == 2)
            #expect(pages[0].systems.allSatisfy { $0.bars.count == 2 && $0.meter == meter && $0.layout == .treble })
            #expect(pages[0].noteCount == song.notes.count)
            #expect(song.notes.indices.allSatisfy { song.page(ofNote: $0) == 0 })
        }
    }

    @Test func grandStaffSongsAreOneSystemAPage() {
        let song = SongGenerator.song(Self.request(level: 2, meter: .threeFour, hands: [.bass, .treble]), seed: 5)
        let pages = song.pages
        #expect(song.layout == .grand)
        #expect(pages.count == 4)
        #expect(pages.allSatisfy { $0.systems.count == 1 && $0.systems[0].layout == .grand && $0.systems[0].bars.count == 2 })
        #expect(pages.flatMap { $0.systems.flatMap(\.notes) } == song.notes)
        // phrase 1 in the bass, phrase 2 in the treble
        #expect(pages[0].systems[0].notes.allSatisfy { $0.clef == .bass })
        #expect(pages[3].systems[0].notes.allSatisfy { $0.clef == .treble })
        var start = 0
        for (i, page) in pages.enumerated() {
            #expect(page.firstNote == start)
            for note in start..<(start + page.noteCount) { #expect(song.page(ofNote: note) == i) }
            start += page.noteCount
        }
    }

    @Test func oneHandEightBarsIsTwoPages() {
        let song = SongGenerator.song(Self.request(level: 2, meter: .fourFour, hands: [.treble, .treble]), seed: 8)
        #expect(song.layout == .treble)
        #expect(song.pages.count == 2)
        #expect(song.pages.allSatisfy { $0.systems.count == 2 })
    }

    // MARK: call and response

    /// Phrase 2 echoes phrase 1 in the other hand, same letters two octaves down or up.
    @Test func callAndResponseEchoesAcrossHands() async {
        let requests = (UInt64(0)..<60).map { (Self.request(level: 2, meter: .fourFour, hands: [.treble, .bass]), $0) }
        let songs = await Self.songs(requests)
        var echoes = 0
        for song in songs where song.form == .abac {
            #expect(song.bars.prefix(4).allSatisfy { $0.clef == .treble })
            #expect(song.bars.suffix(4).allSatisfy { $0.clef == .bass })
            let first = song.bars[0].notes + song.bars[1].notes, third = song.bars[4].notes + song.bars[5].notes
            if first.count == third.count, zip(first, third).allSatisfy({ $0.pitches[0].midi - 24 == $1.pitches[0].midi && $0.value == $1.value }) {
                echoes += 1
            }
        }
        print("songs: \(echoes) of \(songs.filter { $0.form == .abac }.count) a b a c songs echo unit 1 exactly in the other hand")
        #expect(echoes > 10)
    }

    @Test func titlesArePlainWords() {
        var titles = Set<String>()
        for seed in UInt64(0)..<200 {
            for meter in Meter.allCases {
                var rng = SeededRandom(seed: seed)
                let title = SongGenerator.title(meter: meter, using: &rng)
                titles.insert(title)
                let words = title.split(separator: " ").map(String.init)
                #expect((2...3).contains(words.count))
                let moves = meter == .fourFour ? SongGenerator.fourFourMoves : SongGenerator.threeFourMoves
                #expect(moves.contains(words.last!), "\(title)")
                #expect(!title.lowercased().contains("good") && !title.lowercased().contains("great"))
            }
        }
        #expect(titles.count > 150)
    }
}
