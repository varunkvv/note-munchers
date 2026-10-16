import AVFoundation
import NoteCore

/// Turns NoteCore's `Speech` into spoken words. The kid never sees text, so this is
/// how the app talks to him.
@MainActor
final class Voice {
    var isMuted = false
    /// DEBUG: print every line, so demo runs show what was said.
    var logs = false

    private let synth = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?

    init() {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        voice = english.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    func say(_ speech: Speech) {
        let parts = words(for: speech)
        if logs { print("voice: \(parts.map(\.text).joined())") }
        guard !isMuted else { return }
        switch speech {
        case .almost, .sharpHint, .hintListen, .hintShow, .hintLook:
            // feedback on the key he just pressed: the newest one wins
            synth.stopSpeaking(at: .immediate)
        default:
            break
        }
        synth.speak(utterance(parts))
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    // MARK: words

    struct Part {
        var text: String
        /// letter names get an IPA hint, so "A!" is "ay", never "uh"
        var ipa: String?
    }


    /// Lines the app says on its own (not from NoteCore).
    enum Line: String {
        case pickColor = "a new muncher! pick a colour for it"
        case showGrownUp = "show a grown-up!"
        case lookAndShow = "look who ate well today! show a grown-up!"
        case seeYou = "ok! see you next time!"
        case highFive = "high five!"
        case oneMore = "one more round!"
        case allDone = "all done! see you next time!"
    }

    func say(_ line: Line) {
        if logs { print("voice: \(line.rawValue)") }
        guard !isMuted else { return }
        synth.speak(utterance([Part(text: line.rawValue)]))
    }

    /// Placeholder words for each situation. Agent C replaces these with recorded clips
    /// (several takes per line, never the same one twice in a row).
    func words(for speech: Speech) -> [Part] {
        switch speech {
        case .hello:
            return [Part(text: "hi! let's play")]
        case .meetNote(let name):
            // intro, right after its pitch sounds and the key lights up (i do)
            return [Part(text: "this one is new. it's ")] + namePart(name)
        case .listen:
            // a new rhythm lesson, played to him right after: sound before symbol
            return [Part(text: "here's a new one! listen")]
        case .twoAtOnce:
            return [Part(text: "two notes at once! listen")]
        case .almost(let name, let hint):
            let rest = switch hint {
            case .middleC: "this one is the middle C"
            case .higher: "this one is higher up"
            case .lower: "this one is lower down"
            }
            return [Part(text: "that's ")] + namePart(name) + [Part(text: "! \(rest)")]
        case .sharpHint(let name):
            return [Part(text: "that's ")] + namePart(NoteName(rawValue: name.letter.rawValue) ?? name)
                + [Part(text: ". this one is ")] + namePart(name) + [Part(text: ", the black key")]
        case .hintListen:
            return [Part(text: "listen")]
        case .hintShow(let name):
            return [Part(text: "this one is ")] + namePart(name) + [Part(text: ". here it is")]
        case .hintLook:
            return [Part(text: "here they are")]
        // process praise: what he did, never what he is. no "smart", "genius",
        // "talented", "good boy" or empty "great job" (mueller & dweck)
        case .keptTrying:
            return [Part(text: "you kept trying and found it!")]
        case .lookedCarefully:
            return [Part(text: "you looked carefully!")]
        case .holdLonger:
            return [Part(text: "hold this one longer")]
        case .turnOnPiano:
            return [Part(text: "can you turn on the piano?")]
        case .sessionDone:
            return [Part(text: "look who ate well today!")]
        }
    }

    /// "D", or "F sharp". Letters get an IPA hint so "A" is "ay", never "uh".
    private func namePart(_ name: NoteName) -> [Part] {
        let ipa: String = switch name.letter {
        case .a: "ˈeɪ"
        case .b: "ˈbiː"
        case .c: "ˈsiː"
        case .d: "ˈdiː"
        case .e: "ˈiː"
        case .f: "ˈɛf"
        case .g: "ˈdʒiː"
        }
        let letter = Part(text: name.letter.name, ipa: ipa)
        return name.isSharp ? [letter, Part(text: " sharp")] : [letter]
    }

    private func utterance(_ parts: [Part]) -> AVSpeechUtterance {
        let text = NSMutableAttributedString()
        for part in parts {
            var attributes: [NSAttributedString.Key: Any] = [:]
            if let ipa = part.ipa {
                attributes[NSAttributedString.Key(AVSpeechSynthesisIPANotationAttribute)] = ipa
            }
            text.append(NSAttributedString(string: part.text, attributes: attributes))
        }
        let utterance = AVSpeechUtterance(attributedString: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1.12
        return utterance
    }
}
