import Foundation
import Testing
@testable import NoteCore

/// "Dont let him get stuck there" and "come back to it later on"
/// (plans/2026-10-16-progress-and-tunes.md, section 3): in a song the band plays a note
/// he's stuck on, the bar comes back once at the end, and practice shows the note a bit
/// more often for a while.
@Suite struct ComeBackTests {
    // MARK: the band helps

    @Test func twoWrongKeysLightItTwoMorePlayIt() {
        var help = BandHelp(at: 0)
        #expect(help.wrong(at: 1) == .wait)
        #expect(help.wrong(at: 2) == .light)
        #expect(help.isLit)
        #expect(help.wrong(at: 3) == .wait)
        #expect(help.wrong(at: 4) == .play)
    }

    @Test func stuckLightsItThenTheBandPlaysIt() {
        var help = BandHelp(at: 0)
        #expect(help.deadline == BandHelp.lightAfter)
        #expect(help.tick(at: 7.9) == .wait)
        #expect(help.tick(at: 8) == .light)
        #expect(help.deadline == 8 + BandHelp.playAfter)
        #expect(help.tick(at: 17.9) == .wait)
        #expect(help.tick(at: 18) == .play)
    }

    @Test func aKeyStartsTheClockAgain() {
        var help = BandHelp(at: 0)
        _ = help.wrong(at: 6)
        #expect(help.tick(at: 8) == .wait, "he's trying, not stuck")
        #expect(help.tick(at: 14) == .light)
        help.touch(at: 20)
        #expect(help.tick(at: 25) == .wait)
        #expect(help.tick(at: 30) == .play)
    }

    @Test func theRightLetterInAnotherOctaveLightsItAtOnce() {
        var help = BandHelp(at: 0)
        #expect(help.wrong(at: 1, almost: true) == .light)
        #expect(help.wrong(at: 2) == .wait)
        #expect(help.wrong(at: 3, almost: true) == .play)
    }

    @Test func eachNoteStartsFresh() {
        var help = BandHelp(at: 0)
        _ = help.wrong(at: 1)
        _ = help.wrong(at: 2)
        help.next(at: 3)
        #expect(!help.isLit && help.wrongs == 0)
        #expect(help.wrong(at: 4) == .wait)
    }

    // MARK: the bar comes back

    static func song(level: Int = 1, meter: Meter = .fourFour, hands: [Clef] = [.treble, .treble], seed: UInt64 = 3) -> Song {
        SongGenerator.song(SongTests.request(level: level, meter: meter, hands: hands), seed: seed)
    }

    @Test func theHelpedBarIsAPageOfItsOwnAtTheEnd() {
        let song = Self.song()
        let back = song.withComeBack(bar: 1)
        #expect(back.comeBack == 1)
        #expect(back.bars.count == song.bars.count + 1)
        #expect(back.bars.last == song.bars[1])
        #expect(back.writtenBars == song.bars.count && back.writtenNotes == song.notes.count)
        #expect(Array(back.notes.prefix(song.notes.count)) == song.notes)
        let pages = back.pages
        #expect(Array(pages.dropLast()) == song.pages, "the song's own pages don't change")
        let extra = pages.last!
        #expect(extra.firstNote == song.notes.count)
        #expect(extra.systems.count == 1 && extra.systems[0].notes == song.bars[1].notes && extra.systems[0].bars.count == 1)
        for i in song.notes.count..<back.notes.count { #expect(back.page(ofNote: i) == pages.count - 1) }
        #expect(back.hands == song.hands)
        #expect(back.signature != song.signature)
    }

    @Test func onceASong() {
        let back = Self.song().withComeBack(bar: 0)
        #expect(back.withComeBack(bar: 2) == back)
    }

    /// The tag (V7-I) moves to after the come-back bar; the song's last G keeps its own chord.
    @Test func theTagMovesToTheEnd() {
        let song = Self.song()
        let back = song.withComeBack(bar: 2)
        let plan = BackingPlan(song: back), old = BackingPlan(song: song)
        let lastG = song.notes.count - 1
        #expect(old.events(for: lastG).contains { $0.part == .outro })
        #expect(!plan.events(for: lastG).contains { $0.part == .outro })
        #expect(plan.events(for: lastG).contains { $0.part == .chord }, "the I chord with his last G")
        #expect(plan.events(for: back.notes.count - 1).filter { $0.part == .outro }.count == 2)
        // the bar's own chords come back with it
        let start = back.barStarts.last!
        #expect(plan.events(for: start).contains { $0.part == .bass || $0.part == .chord })
        for i in 0..<lastG { #expect(plan.events(for: i) == old.events(for: i)) }
    }

    @Test func theFollowerKeepsHisTempo() {
        let song = Self.song()
        var follower = BackingFollower(plan: BackingPlan(song: song))
        var t = 0.0
        for i in 0..<(song.notes.count - 1) {
            _ = follower.played(i, at: t)
            t += song.notes[i].span * 0.6
        }
        let beat = follower.beat
        follower.replan(BackingPlan(song: song.withComeBack(bar: 0)))
        #expect(follower.beat == beat)
        let last = follower.played(song.notes.count - 1, at: t)
        #expect(!last.contains { $0.event.part == .outro })
        #expect(abs(follower.beat - beat) < 0.05)
    }

    // MARK: practice shows it a bit more

    func engine() -> MasteryEngine { NoteCoreTests.engine(in: "1.4", seed: 3) }

    @Test func theFlagIsNotAMiss() {
        var engine = engine()
        let b = key("treble:B4")
        for _ in 0..<3 { engine.play(b) }
        let before = engine.stats(for: b)
        engine.comeBack(to: [b, b])
        let after = engine.stats(for: b)
        #expect(after.comeBack == engine.config.comeBackPlays)
        #expect(after.box == before.box && after.recent == before.recent && after.attempts == before.attempts)
        #expect(engine.comeBackWeight(b) == engine.config.comeBackBoost)
        #expect(engine.comeBackWeight(key("treble:A4")) == 1)
    }

    @Test func twoRightFirstTriesClearIt() {
        var engine = engine()
        let b = key("treble:B4")
        engine.comeBack(to: [b])
        engine.play(b, right: false)
        #expect(engine.stats(for: b).comeBack == 2, "a miss doesn't clear it")
        engine.play(b)
        #expect(engine.stats(for: b).comeBack == 1)
        engine.play(b)
        #expect(engine.stats(for: b).comeBack == 0)
        #expect(engine.comeBackWeight(b) == 1)
    }

    /// Over many screens a flagged note comes up clearly more often than without the flag.
    @Test func itComesUpMoreOften() {
        func share(flagged: Bool) -> Double {
            var engine = engine()
            for key in engine.pool { for _ in 0..<3 { engine.play(key) } }
            var state = engine.state
            state.newest = [:]
            engine.state = state
            let b = key("treble:B4")
            var rng = SeededRandom(seed: 11)
            var count = 0, all = 0
            for _ in 0..<400 {
                if flagged { engine.comeBack(to: [b]) } // keep it flagged
                let pick = engine.pickScreen(clef: .treble, using: &rng)
                let keys = pick.item.notes.flatMap(\.keys).filter { $0.clef == .treble }
                count += keys.filter { $0 == b }.count
                all += keys.count
                engine.playPick(pick)
            }
            return Double(count) / Double(max(1, all))
        }
        let plain = share(flagged: false), more = share(flagged: true)
        print("come back: B4 is \(Int(plain * 100))% of treble notes, \(Int(more * 100))% while flagged")
        #expect(more > plain * 1.25, "\(plain) -> \(more)")
    }

    @Test func savedStatsWithoutTheFlagStillDecode() throws {
        var engine = engine()
        engine.comeBack(to: [key("treble:B4")])
        let data = try JSONEncoder().encode(engine.state)
        let back = try JSONDecoder().decode(MasteryState.self, from: data)
        #expect(back.stats["treble:B4"]?.comeBack == 2)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var stats = json["stats"] as! [String: Any]
        var b = stats["treble:B4"] as! [String: Any]
        b.removeValue(forKey: "comeBack")
        stats["treble:B4"] = b
        json["stats"] = stats
        let old = try JSONDecoder().decode(MasteryState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.stats["treble:B4"]?.comeBack == 0)
        #expect(old.stats["treble:B4"]?.box == back.stats["treble:B4"]?.box)
        // a saved config from before has the new knobs at their defaults
        var config = try JSONSerialization.jsonObject(with: JSONEncoder().encode(NoteCoreConfig())) as! [String: Any]
        config.removeValue(forKey: "comeBackBoost")
        config.removeValue(forKey: "comeBackPlays")
        let decoded = try JSONDecoder().decode(NoteCoreConfig.self, from: JSONSerialization.data(withJSONObject: config))
        #expect(decoded.comeBackPlays == 2 && decoded.comeBackBoost == 2)
    }
}
