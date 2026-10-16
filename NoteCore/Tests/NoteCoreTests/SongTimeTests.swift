import Foundation
import Testing
@testable import NoteCore

/// When song time shows up and what goes into a song (SongTime.swift).
@Suite struct SongTimeTests {
    var stay: NoteCoreConfig {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        return config
    }

    func engine(_ lesson: LessonID) -> MasteryEngine {
        var engine = MasteryEngine(config: stay, state: MasteryState(seed: 3))
        engine.moveToLesson(lesson)
        engine.introduceAll()
        return engine
    }

    /// Box 4: three right first tries from box 1.
    func solid(_ engine: inout MasteryEngine, _ ids: [String]) {
        for id in ids { for _ in 0..<3 { engine.play(key(id)) } }
    }

    @Test func aNewKidHasNoSongTime() {
        let engine = MasteryEngine()
        #expect(!engine.canPlaySongs)
        #expect(engine.songRequest(seed: 1) == nil)
        #expect(engine.makeSong(seed: 1) == nil)
    }

    @Test func threeSolidNotesWithGAndAInAClef() {
        var engine = engine("1.4")
        #expect(!engine.canPlaySongs)
        solid(&engine, ["treble:G4", "treble:A4"])
        #expect(!engine.canPlaySongs, "two notes isn't enough")
        solid(&engine, ["treble:B4"])
        #expect(engine.solidNotes(.treble).map(\.id) == ["treble:G4", "treble:A4", "treble:B4"])
        #expect(engine.songClefs == [.treble])
        #expect(engine.solidNotes(.bass).isEmpty)
    }

    @Test func noAMeansNoSongYet() {
        var engine = engine("2.1")
        solid(&engine, ["treble:G4", "treble:B4", "treble:C5", "treble:D5"])
        #expect(engine.solidNotes(.treble).count == 4)
        #expect(engine.songClefs.isEmpty, "every level 1 song ends A to G")
    }

    /// Level 1 songs need G, A and one more: none in 1.1, and in 1.2 once B is drilled
    /// (box 3 and its 10 plays). Notes from outside his lesson never count.
    @Test func levelOneSongsOpenInOnePointTwo() {
        var engine = MasteryEngine(config: stay, state: MasteryState(seed: 3))
        engine.introduceAll()
        solid(&engine, ["treble:G4", "treble:A4"])
        #expect(!engine.canPlaySongs, "1.1 has only G and A")
        // an old save with B solid doesn't open it in 1.1
        var state = engine.state
        for id in ["treble:B4", "treble:C5"] {
            var s = ItemStats()
            s.box = 4
            s.attempts = 6
            state.stats[id] = s
            state.unlocked.insert(id)
            state.introduced.insert(id)
        }
        engine.state = state
        #expect(!engine.canPlaySongs, "B and C aren't in 1.1")
        engine.moveToLesson("1.2")
        #expect(!engine.canPlaySongs, "B is the newest note until it's drilled")
        for _ in 0..<10 { engine.play(key("treble:B4")) }
        #expect(engine.hasMinPlays(key("treble:B4")))
        #expect(engine.solidNotes(.treble).map(\.id) == ["treble:G4", "treble:A4", "treble:B4"])
        #expect(engine.songClefs == [.treble])
    }

    @Test func boxTwoIsntSolidYet() {
        var engine = engine("1.4")
        for id in ["treble:G4", "treble:A4", "treble:B4"] { engine.play(key(id)) }
        #expect(engine.stats(for: key("treble:G4")).box == 2)
        #expect(engine.solidNotes(.treble).isEmpty)
    }

    @Test func theNewestNoteIsNeverInASong() {
        var engine = engine("1.4")
        solid(&engine, ["treble:G4", "treble:A4", "treble:B4", "treble:C5"])
        var state = engine.state
        state.newest = ["treble": ["treble:C5"]]
        engine.state = state
        #expect(engine.solidNotes(.treble).map(\.id) == ["treble:G4", "treble:A4", "treble:B4"])
    }

    @Test func songRanges() {
        #expect(MasteryEngine.songRange(level: 1, clef: .treble).map(\.name) == ["G4", "A4", "B4", "C5", "D5"])
        #expect(MasteryEngine.songRange(level: 4, clef: .bass).map(\.name) == ["G2", "A2", "B2", "C3", "D3"])
        #expect(MasteryEngine.songRange(level: 3, clef: .treble).map(\.name) == ["G4", "A4", "B4", "C5", "D5", "E5", "F#5", "G5"])
        #expect(MasteryEngine.songRange(level: 3, clef: .bass).map(\.name) == ["G2", "A2", "B2", "C3", "D3", "E3", "F#3", "G3"])
    }

    @Test func levelOneIsFourBarsInOneClef() {
        var engine = engine("1.4")
        solid(&engine, ["treble:G4", "treble:A4", "treble:B4", "bass:G2", "bass:A2", "bass:B2"])
        var meters = Set<Meter>()
        for seed in UInt64(0)..<30 {
            let r = engine.songRequest(seed: seed)!
            #expect(r.level == 1 && r.bars == 4)
            #expect(r.hands[0] == r.hands[1])
            #expect(r.notes(r.hands[0]).count == 3)
            #expect(r.notes(r.hands[0] == .treble ? .bass : .treble).isEmpty)
            meters.insert(r.meter)
        }
        #expect(meters.count == 2)
    }

    @Test func levelTwoIsCallAndResponse() {
        var engine = engine("2.1")
        solid(&engine, MasteryEngine.songRange(level: 2, clef: .treble).map { "treble:\($0.name)" }
              + MasteryEngine.songRange(level: 2, clef: .bass).map { "bass:\($0.name)" })
        var firsts = Set<Clef>()
        for seed in UInt64(0)..<30 {
            let r = engine.songRequest(seed: seed)!
            #expect(r.bars == 8 && r.layout == .grand && r.hands[0] != r.hands[1])
            firsts.insert(r.hands[0])
        }
        #expect(firsts.count == 2, "either hand can ask")
    }

    @Test func levelTwoWithOneClefIsOneHand() {
        var engine = engine("2.1")
        solid(&engine, ["bass:G2", "bass:A2", "bass:B2", "bass:C3"])
        let r = engine.songRequest(seed: 4)!
        #expect(r.hands == [.bass, .bass] && r.bars == 8 && r.layout == .bass)
    }

    /// Level 3: five notes a song, the upper five with the F# or G position.
    @Test func levelThreeTakesFiveOfTheOctave() {
        var engine = engine("3.6")
        let all = MasteryEngine.songRange(level: 3, clef: .treble).map { "treble:\($0.name)" } + MasteryEngine.songRange(level: 3, clef: .bass).map { "bass:\($0.name)" }
        solid(&engine, all)
        var upper = 0
        for seed in UInt64(0)..<40 {
            let r = engine.songRequest(seed: seed)!
            for clef in Clef.allCases {
                let notes = r.notes(clef)
                #expect(notes.count == 5)
                #expect(notes.contains { $0.letter == .g })
                if notes.contains(where: { !$0.isWhiteKey }) { upper += 1 }
            }
            #expect(!SongGenerator.song(r, seed: seed).isFallback)
        }
        #expect(upper > 20 && upper < 80, "\(upper) of 80 hands were the upper five")
    }

    @Test func levelOneTakesTurnsBetweenClefs() {
        var engine = engine("1.4")
        solid(&engine, ["treble:G4", "treble:A4", "treble:B4", "treble:C5", "bass:G2", "bass:A2", "bass:B2"])
        var clefs: [Clef] = []
        for seed in UInt64(0)..<40 {
            let song = engine.makeSong(seed: seed)!
            clefs.append(song.hands[0])
            engine.rememberSong(song)
        }
        #expect(maxRun(clefs) <= 2)
        #expect(clefs.filter { $0 == .treble }.count >= 10 && clefs.filter { $0 == .bass }.count >= 10)
    }

    @Test func rememberedSongsDontComeBack() {
        var engine = engine("2.1")
        solid(&engine, MasteryEngine.songRange(level: 2, clef: .treble).map { "treble:\($0.name)" })
        var signatures: [String] = []
        for seed in UInt64(0)..<30 {
            let song = engine.makeSong(seed: seed)!
            #expect(!signatures.suffix(20).contains(song.signature))
            signatures.append(song.signature)
            engine.rememberSong(song)
        }
        #expect(engine.state.recentSongs.count == MasteryEngine.recentSongCount)
        #expect(engine.state.recentSongs.last?.signature == signatures.last)
    }

    @Test func savedStateWithoutSongsStillDecodes() throws {
        var engine = engine("1.4")
        solid(&engine, ["treble:G4", "treble:A4", "treble:B4"])
        engine.rememberSong(engine.makeSong(seed: 1)!)
        let data = try JSONEncoder().encode(engine.state)
        let back = try JSONDecoder().decode(MasteryState.self, from: data)
        #expect(back == engine.state)
        #expect(back.recentSongs.count == 1)
        // an older build's save has no recentSongs at all
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "recentSongs")
        let old = try JSONDecoder().decode(MasteryState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.recentSongs.isEmpty)
        #expect(old.stats == engine.state.stats)
    }
}
