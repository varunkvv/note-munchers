import Foundation
import Testing
@testable import NoteCore

/// The familiar tunes shelf (plans/2026-10-16-progress-and-tunes.md, section 4).
@Suite struct FamiliarTunesTests {
    func engine(_ lesson: LessonID, solid ids: [String]) -> MasteryEngine {
        var engine = NoteCoreTests.engine(in: lesson, seed: 3)
        for id in ids { for _ in 0..<3 { engine.play(key(id)) } }
        return engine
    }

    static let gPosition = ["G4", "A4", "B4", "C5", "D5"].map { "treble:\($0)" } + ["G2", "A2", "B2", "C3", "D3"].map { "bass:\($0)" }

    /// Some made-up songs first, so tunes can come.
    func madeUp(_ engine: inout MasteryEngine, _ count: Int = 3) {
        for i in 0..<count {
            engine.rememberSong(SongGenerator.song(engine.songRequest(seed: UInt64(1000 + i))!, seed: UInt64(1000 + i)))
        }
    }

    @Test func theTunesAreInGPositionWithChords() {
        #expect(Tune.all.map(\.name) == ["Hot Cross Buns", "Mary Had a Little Lamb", "Ode to Joy", "Au Clair de la Lune", "Lightly Row", "Jingle Bells"])
        for tune in Tune.all {
            for clef in Clef.allCases {
                let range = Set(MasteryEngine.songRange(level: 1, clef: clef).map { NoteKey(clef, $0) })
                #expect(tune.allKeys(clef).isSubset(of: range), "\(tune.name) \(clef)")
            }
            #expect(tune.chords.count == tune.bars.count)
            #expect(tune.bars.joined().allSatisfy { $0.value != .eighth && !$0.value.isDotted || $0.value == .dottedHalf }, "\(tune.name): no eighths or dotted quarters")
            #expect(tune.bars.last!.last!.degree == 0, "\(tune.name) ends on G")
            // every beat 1 is in its chord, so the backing doesn't clash where it sounds
            for (b, bar) in tune.keys(.treble).enumerated() { #expect(tune.chords[b][0].contains(bar[0].pitch), "\(tune.name) bar \(b + 1)") }
        }
        #expect(Tune.all.filter { $0.level == 2 }.map(\.name) == ["Lightly Row", "Jingle Bells"])
    }

    @Test func aTuneIsAMysterySongWithItsNameForTheEnd() {
        let engine = engine("1.4", solid: Self.gPosition)
        let mary = Tune.all[1]
        let song = engine.song(mary, clef: .bass, seed: 9)
        #expect(song.title == "Mystery song!" && song.tune == "Mary Had a Little Lamb")
        #expect(song.layout == .bass && song.keySignature == .none && song.level == 1)
        #expect(song.bars.count == 8 && song.pages.count == 2)
        #expect(song.notes.map { $0.pitches[0].name }.prefix(4) == ["B2", "A2", "G2", "A2"])
        #expect(BackingPlan(song: song).events.contains { $0.part == .outro })
        #expect(PlayedSong(song).tune == "Mary Had a Little Lamb")
        // level 3 reads in G major
        let three = NoteCoreTests.engine(in: "3.6", seed: 3)
        #expect(three.song(mary, clef: .treble, seed: 1).keySignature == .gMajor)
        // hot cross buns' five bars are two pages: four bars, then one
        #expect(engine.song(Tune.all[0], clef: .treble, seed: 1).pages.map(\.systems.count) == [2, 1])
    }

    @Test func onlyTunesWhoseEveryNoteIsSolid() {
        var engine = engine("1.4", solid: ["treble:G4", "treble:A4", "treble:B4"])
        #expect(engine.familiarTunes.map(\.tune.name) == ["Hot Cross Buns", "Au Clair de la Lune"], "Mary needs D, Ode needs C and D")
        #expect(engine.familiarTunes.allSatisfy { $0.clefs == [.treble] })
        for id in ["treble:C5", "treble:D5", "bass:G2", "bass:A2", "bass:B2"] { for _ in 0..<3 { engine.play(key(id)) } }
        var state = engine.state
        state.newest = [:] // D isn't the newest any more
        engine.state = state
        let names = engine.familiarTunes.map(\.tune.name)
        #expect(names == ["Hot Cross Buns", "Mary Had a Little Lamb", "Ode to Joy", "Au Clair de la Lune"], "level 2's tunes wait for level 2")
        #expect(engine.familiarTunes.first { $0.tune.name == "Hot Cross Buns" }?.clefs == [.treble, .bass])
        let two = self.engine("2.1", solid: Self.gPosition)
        #expect(two.familiarTunes.count == Tune.all.count)
    }

    /// Never before a few made-up songs, never twice running, about 1 in 6, and the one
    /// he's had least lately: not one of his last 20 songs while another tune isn't.
    @Test func nowAndThen() {
        var engine = engine("2.1", solid: Self.gPosition)
        for seed in UInt64(0)..<200 { #expect(engine.familiarTune(seed: seed) == nil, "no tune before \(MasteryEngine.madeUpBeforeTunes) made-up songs") }
        madeUp(&engine)
        var tunes: [String] = []
        var count = 0
        var lastWasTune = false
        for seed in UInt64(0)..<600 {
            let song = engine.makeSong(seed: seed)!
            if let name = song.tune {
                #expect(!lastWasTune, "two tunes in a row at seed \(seed)")
                let fresh = Tune.all.map(\.name).filter { tune in !engine.state.recentSongs.contains { $0.tune == tune } }
                #expect(fresh.isEmpty || fresh.contains(name), "\(name) came back within 20 songs while \(fresh) didn't")
                tunes.append(name)
                count += 1
            }
            lastWasTune = song.tune != nil
            engine.rememberSong(song)
        }
        let share = Double(count) / 600
        print("tunes: \(count) of 600 songs (\(Int(share * 100))%), first ones \(tunes.prefix(8))")
        #expect(share > 0.09 && share < 0.22, "\(share)")
        #expect(Set(tunes) == Set(Tune.all.map(\.name)), "every tune comes up: \(Set(tunes))")
    }

    @Test func aTuneTakesTurnsBetweenTheClefs() {
        var engine = engine("1.4", solid: Self.gPosition)
        madeUp(&engine)
        let last = engine.state.recentSongs.last!.hands[0]
        let seed = (UInt64(0)..<2000).first { engine.familiarTune(seed: $0) != nil }!
        #expect(engine.familiarTune(seed: seed)!.hands[0] != last)
    }

    /// His saved songs from before the shelf decode, as made-up songs.
    @Test func savedSongsWithoutTunesStillDecode() throws {
        var engine = engine("1.4", solid: Self.gPosition)
        madeUp(&engine)
        engine.rememberSong(engine.song(Tune.all[0], clef: .treble, seed: 1))
        let data = try JSONEncoder().encode(engine.state)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let songs = (json["recentSongs"] as! [[String: Any]]).map { song -> [String: Any] in
            var song = song
            song.removeValue(forKey: "tune")
            return song
        }
        json["recentSongs"] = songs
        let old = try JSONDecoder().decode(MasteryState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.recentSongs.count == 4 && old.recentSongs.allSatisfy { $0.tune == nil })
        #expect(try JSONDecoder().decode(MasteryState.self, from: data).recentSongs.last?.tune == "Hot Cross Buns")
    }

    /// Drill screens keep taking bits of the level 1 tunes in level 1, and never a bit
    /// that's one key all through.
    @Test func drillsTakeTunesFromHisLevel() {
        for (lesson, allowed) in [("1.5", Tune.all.filter { $0.level == 1 }), ("2.4", Tune.all)] {
            var engine = NoteCoreTests.engine(in: lesson, seed: 3)
            var rng = SeededRandom(seed: 5)
            var seen = Set<String>()
            for _ in 0..<300 {
                guard let pick = engine.pickDrill(.tune, using: &rng) else { continue }
                let keys = pick.item.notes.flatMap(\.keys)
                #expect(Set(keys).count > 1, "\(lesson): \(pick.item.id)")
                let clef = keys[0].clef
                let tune = allowed.first { tune in Array(tune.keys(clef).joined().prefix(keys.count)) == keys }
                #expect(tune != nil, "\(lesson): \(pick.item.id)")
                if let tune { seen.insert(tune.name) }
            }
            if lesson == "2.4" { #expect(seen.contains("Lightly Row"), "\(seen)") }
            #expect(!seen.contains("Jingle Bells"))
        }
    }
}
