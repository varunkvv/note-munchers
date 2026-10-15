import Foundation
import Testing
@testable import NoteCore

@Suite struct CurriculumTests {
    let curriculum = Curriculum.standard

    @Test func twelveUnitsNumberedInOrder() {
        #expect(curriculum.units.map(\.number) == Array(1...12))
    }

    @Test func itemIDsAreUniqueAndResolve() {
        let ids = curriculum.allItems.map(\.id)
        #expect(Set(ids).count == ids.count)
        for id in ids {
            #expect(curriculum.item(id)?.id == id)
        }
    }

    @Test func idsAreReadable() {
        #expect(curriculum.unit(1)!.newItems[0].id == "treble:C4")
        #expect(curriculum.unit(2)!.newItems[0].id == "bass:C4")
        #expect(curriculum.unit(9)!.newItems[0].id == "treble:C4+E4+G4")
        #expect(curriculum.unit(10)!.newItems[0].id == "treble:G4/q-G4/q-G4/h")
    }

    @Test func unitOneStartsWithCAndGTogether() {
        let unit = curriculum.unit(1)!
        #expect(unit.startCount == 2)
        #expect(unit.newItems.prefix(2).map(\.id) == ["treble:C4", "treble:G4"])
        #expect(unit.newItems.map(\.id) == ["treble:C4", "treble:G4", "treble:E4", "treble:D4", "treble:F4"])
    }

    @Test func octavePolicyIsLenientOnlyForUnitsOneToThree() {
        for unit in curriculum.units {
            #expect(unit.octavePolicy == (unit.number <= 3 ? .lenient : .strict), "unit \(unit.number)")
        }
    }

    /// The no-3-in-a-row rule needs 2+ items in the pool from the first prompt.
    @Test func everyUnitStartsWithAtLeastTwoItemsInThePool() {
        for unit in curriculum.units {
            let reviewCount = unit.reviews.reduce(0) { $0 + curriculum.unit($1)!.newItems.count }
            #expect(unit.startCount + reviewCount >= 2, "unit \(unit.number)")
            #expect(unit.reviews.allSatisfy { $0 < unit.number }, "unit \(unit.number) reviews only earlier units")
        }
    }

    @Test func itemsFitTheirUnitStaff() {
        for unit in curriculum.units {
            let pool = unit.newItems + unit.reviews.flatMap { curriculum.unit($0)!.newItems }
            for item in pool {
                #expect(unit.staff.contains(item.clef), "unit \(unit.number) \(item.id)")
            }
        }
    }

    @Test func unitKinds() {
        let kinds = curriculum.units.map { Set($0.newItems.map(\.kind)) }
        for number in [1, 2, 4, 5, 6] {
            #expect(kinds[number - 1] == [.note], "unit \(number)")
        }
        #expect(curriculum.unit(3)!.newItems.isEmpty)
        #expect(kinds[6] == [.group])
        #expect(kinds[7] == [.chord])
        #expect(kinds[8] == [.chord])
        for number in 10...12 {
            #expect(kinds[number - 1] == [.rhythm], "unit \(number)")
        }
    }

    @Test func groupsAreTwoToFourNotes() {
        for item in curriculum.unit(7)!.newItems {
            #expect((2...4).contains(item.notes.count), "\(item.id)")
        }
    }

    @Test func unitEightIsThirdsAndFifths() {
        for item in curriculum.unit(8)!.newItems {
            let pitches = item.notes[0].pitches
            #expect(pitches.count == 2)
            let steps = pitches[1].diatonicIndex - pitches[0].diatonicIndex
            #expect(steps == 2 || steps == 4, "\(item.id) is a 3rd or a 5th")
        }
    }

    @Test func unitNineIsCFAndGTriads() {
        let roots = curriculum.unit(9)!.newItems.map { $0.notes[0].pitches[0].letter! }
        #expect(Set(roots) == [.c, .f, .g])
        for item in curriculum.unit(9)!.newItems {
            let p = item.notes[0].pitches
            #expect(p.count == 3)
            #expect(p[1].midi - p[0].midi == 4 && p[2].midi - p[1].midi == 3, "\(item.id) is a root position major triad")
        }
    }

    @Test func rhythmItemsAreWholeBarsAndMixLengths() {
        for number in 10...12 {
            for item in curriculum.unit(number)!.newItems {
                let values = item.values!
                #expect(item.totalBeats.truncatingRemainder(dividingBy: 4) == 0, "\(item.id) fills whole 4/4 bars")
                #expect(Set(values).count >= 2, "\(item.id) mixes lengths, or rhythm can't be judged at his tempo")
                #expect(values.count >= 3, "\(item.id) has 3+ notes so the tempo estimate is stable")
            }
        }
    }

    @Test func unitTenIsQuartersAndHalvesOnOneNote() {
        for item in curriculum.unit(10)!.newItems {
            #expect(Set(item.notes.flatMap(\.pitches)) == [Pitch(.g, 4)])
            #expect(Set(item.values!).isSubset(of: [.quarter, .half]))
        }
        #expect(curriculum.unit(11)!.newItems.allSatisfy { $0.values!.contains(.eighth) })
    }

    @Test func unitTwelveLinesAreFourToEightNotes() {
        for item in curriculum.unit(12)!.newItems {
            #expect((4...8).contains(item.notes.count), "\(item.id)")
            #expect(Set(item.notes.flatMap(\.pitches)).count >= 2, "\(item.id) has pitch AND rhythm")
        }
    }

    @Test func eighthsComeInBeamedPairs() {
        for number in 11...12 {
            for item in curriculum.unit(number)!.newItems {
                let eighths = item.values!.filter { $0 == .eighth }.count
                #expect(item.beamedPairStarts.count * 2 == eighths, "\(item.id)")
            }
        }
        let item = PracticeItem(.treble, [NoteValue.quarter, .eighth, .eighth, .quarter, .quarter].map { WrittenNote([Pitch(.g, 4)], $0) })
        #expect(item.beamedPairStarts == [1])
    }

    @Test func playbackSchedule() {
        let item = curriculum.unit(11)!.newItems[0] // e e q h
        let schedule = item.playback(beat: 0.5)
        #expect(schedule.map(\.start) == [0, 0.25, 0.5, 1.0])
        #expect(schedule.map(\.duration) == [0.25, 0.25, 0.5, 1.0])
    }

    @Test func itemsAreCodable() throws {
        let item = curriculum.unit(12)!.newItems[1]
        let data = try JSONEncoder().encode(item)
        #expect(try JSONDecoder().decode(PracticeItem.self, from: data) == item)
    }
}
