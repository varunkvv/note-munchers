import Testing
@testable import NoteCore

/// The piano part and how it follows him (composer.md, "following him").
@Suite struct BackingTests {
    static func song(level: Int, meter: Meter = .fourFour, hands: [Clef] = [.treble, .bass], seed: UInt64 = 11) -> Song {
        SongGenerator.song(SongTests.request(level: level, meter: meter, hands: level == 1 ? [hands[0], hands[0]] : hands), seed: seed)
    }

    @Test func levelsOneAndTwoOnlySoundWithHisKeys() {
        for level in [1, 2] {
            for meter in Meter.allCases {
                let plan = BackingPlan(song: Self.song(level: level, meter: meter))
                #expect(plan.pattern == .anchored)
                let anchored = plan.events.filter { $0.part != .outro }.allSatisfy { $0.isAnchored }
                #expect(anchored)
                // every bar's first note sounds the bass and the chord
                let song = Self.song(level: level, meter: meter)
                for start in song.barStarts {
                    let parts = plan.events(for: start).map(\.part)
                    #expect(parts.contains(.chord))
                    if song.bars[song.barOfNote[start]].clef == .treble { #expect(parts.contains(.bass)) }
                }
            }
        }
    }

    @Test func fillersNeverRunPastTheNoteHesHolding() {
        for level in 1...5 {
            for meter in Meter.allCases {
                let song = Self.song(level: level, meter: meter)
                let plan = BackingPlan(song: song)
                for event in plan.events where event.part != .outro {
                    #expect(event.offset < song.notes[event.note].value.beats, "level \(level): \(event)")
                }
                if level >= 3 { #expect(plan.events.contains { !$0.isAnchored && $0.part != .outro }) }
            }
        }
    }

    /// Away from the hand that's playing: under a treble tune, over a bass tune.
    @Test func thePartStaysOutOfHisWay() {
        for level in 1...5 {
            let song = Self.song(level: level, hands: [.treble, .bass])
            let plan = BackingPlan(song: song)
            for event in plan.events where event.part != .outro {
                let clef = song.notes[event.note].clef
                if clef == .treble {
                    #expect(event.pitches.allSatisfy { $0 < Pitch(.g, 4) }, "\(event)")
                } else {
                    #expect(event.pitches.allSatisfy { $0 > Pitch(.g, 3) }, "\(event)")
                    #expect(event.part != .bass)
                }
            }
        }
    }

    @Test func introSetsTheKeyAndTheTagEndsIt() {
        let song = Self.song(level: 2, hands: [.bass, .treble])
        let plan = BackingPlan(song: song)
        #expect(plan.intro.rolled)
        #expect(plan.intro.pitches.allSatisfy { Chord.I.contains($0) })
        #expect(plan.intro.pitches.allSatisfy { $0 > Pitch(.g, 3) }, "phrase 1 is in the bass: the intro chord sits above it")
        let tag = plan.events.filter { $0.part == .outro }
        #expect(tag.count == 2)
        #expect(tag.allSatisfy { $0.note == song.notes.count - 1 })
        #expect(tag[0].pitches.contains { $0.pitchClass == 0 }, "V7 has the C")
        #expect(tag[1].pitches.allSatisfy { Chord.I.contains($0) } && tag[1].rolled)
        #expect(tag[0].offset < tag[1].offset)
    }

    // MARK: following him

    struct Run {
        var presses: [Double] = []
        var sounded: [(event: TimedBackingEvent, press: Int)] = []
        var cancelled = 0
        var beats: [Double] = []
    }

    /// Plays `song` with each gap `beat(i)` seconds a quarter (plus `pause` seconds before
    /// note `pauseAt`), the way the app does: each key sounds what the follower returns,
    /// and drops whatever was still waiting from the key before.
    func run(_ song: Song, beat: (Int) -> Double, pauseAt: Int? = nil, pause: Double = 6) -> Run {
        var follower = BackingFollower(plan: BackingPlan(song: song))
        var r = Run()
        var t = 0.0
        var pending: [(event: TimedBackingEvent, press: Int)] = []
        for i in song.notes.indices {
            if i > 0 {
                t += song.notes[i - 1].span * beat(i - 1)
                if i == pauseAt { t += pause }
            }
            // his key: anything still waiting is dropped
            for p in pending { if p.event.time < t - 1e-9 { r.sounded.append(p) } else { r.cancelled += 1 } }
            pending = []
            r.presses.append(t)
            let out = follower.played(i, at: t)
            r.beats.append(follower.beat)
            for event in out {
                #expect(event.time >= t - 1e-9, "nothing sounds before his key")
                pending.append((event, i))
            }
        }
        r.sounded += pending
        return r
    }

    @Test(arguments: [3, 4, 5])
    func followsSteadySlowAndFast(level: Int) {
        for meter in Meter.allCases {
            let song = Self.song(level: level, meter: meter)
            for tempo in [0.4, 0.8, 1.4] {
                let r = run(song, beat: { _ in tempo })
                #expect(abs(r.beats.last! - tempo) < 0.02, "level \(level) at \(tempo): beat \(r.beats.last!)")
                // at his own steady tempo every filler lands before his next key
                let late = r.sounded.filter { $0.press + 1 < r.presses.count && $0.event.time >= r.presses[$0.press + 1] - 1e-9 }
                #expect(late.isEmpty)
                #expect(r.cancelled <= 4, "level \(level) at \(tempo): \(r.cancelled) fillers dropped") // the first notes, before it knows his beat
            }
        }
    }

    @Test func verySlowIsClampedNotChased() {
        let r = run(Self.song(level: 3), beat: { _ in 3.0 })
        #expect(r.beats.allSatisfy { BackingFollower.beatRange.contains($0) })
        #expect(r.beats.last! == BackingFollower.beatRange.upperBound)
    }

    @Test func jitteryTimingStaysInsideEachNote() {
        let song = Self.song(level: 4, meter: .threeFour)
        var rng = SeededRandom(seed: 3)
        let jitter = song.notes.indices.map { _ in 0.8 * (0.7 + 0.6 * unitInterval(&rng)) }
        let r = run(song, beat: { jitter[$0] })
        #expect(r.beats.allSatisfy { BackingFollower.beatRange.contains($0) && abs($0 - 0.8) < 0.25 })
        for (event, press) in r.sounded where event.event.part != .outro {
            // never past the written end of the note at his beat then
            #expect(event.time < r.presses[press] + song.notes[press].value.beats * r.beats[press] + 1e-9)
            // and a filler never lands on or after his next key (those are dropped)
            if press + 1 < r.presses.count { #expect(event.time < r.presses[press + 1]) }
        }
    }

    /// A 6s stop to read: the part decays and waits, and his tempo isn't stretched by it.
    @Test(arguments: [3, 5])
    func aSixSecondPauseIsReadingNotTempo(level: Int) {
        let song = Self.song(level: level)
        let at = song.notes.count / 2
        let r = run(song, beat: { _ in 0.7 }, pauseAt: at)
        #expect(abs(r.beats[at] - r.beats[at - 1]) < 0.01, "beat before \(r.beats[at - 1]), after \(r.beats[at])")
        #expect(abs(r.beats[at] - 0.7) < 0.02)
        // nothing sounds in the pause after the note before it has run out
        let quiet = (r.presses[at - 1] + song.notes[at - 1].span * 0.7 + 1e-6)..<r.presses[at]
        #expect(!r.sounded.contains { quiet.contains($0.event.time) && $0.event.event.part != .outro })
    }

    /// The play button between two keys: that gap isn't his tempo, even early on.
    @Test func aRestIsntCounted() {
        let song = Self.song(level: 3)
        var follower = BackingFollower(plan: BackingPlan(song: song))
        var t = 0.0
        _ = follower.played(0, at: t)
        t += song.notes[0].span * 0.6
        _ = follower.played(1, at: t)
        #expect(abs(follower.beat - 0.6) < 1e-9)
        follower.rest()
        t += 5
        _ = follower.played(2, at: t)
        #expect(abs(follower.beat - 0.6) < 1e-9)
        t += song.notes[2].span * 0.6
        _ = follower.played(3, at: t)
        #expect(abs(follower.beat - 0.6) < 1e-9)
    }

    @Test func anchoredLevelsSoundOnlyOnHisKeys() {
        let song = Self.song(level: 1)
        var rng = SeededRandom(seed: 9)
        let jitter = song.notes.indices.map { _ in 0.5 + 1.5 * unitInterval(&rng) }
        let r = run(song, beat: { jitter[$0] }, pauseAt: 4)
        for (event, press) in r.sounded where event.event.part != .outro {
            #expect(abs(event.time - r.presses[press]) < 1e-9)
        }
        #expect(r.cancelled == 0)
    }

    @Test func listenTimelineIsTheWholePartInOrder() {
        let song = Self.song(level: 3, meter: .threeFour)
        let plan = BackingPlan(song: song)
        let timeline = plan.timeline(beat: 0.6)
        #expect(timeline.first?.event == plan.intro && timeline.first!.time < 0)
        #expect(timeline.count == plan.events.count + 1)
        let starts = song.startBeats
        for t in timeline.dropFirst() {
            #expect(abs(t.time - (starts[t.event.note] + t.event.offset) * 0.6) < 1e-9)
        }
    }
}
