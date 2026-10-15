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
    private var lastPraise: String?

    init() {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        voice = english.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    func say(_ speech: Speech) {
        let parts = words(for: speech)
        if logs { print("voice: \(parts.map(\.text).joined())") }
        guard !isMuted else { return }
        switch speech {
        case .letter, .letters:
            // he may play faster than the voice talks. the newest letter wins
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

    static let praise = [
        "yum!", "nice reading!", "you found it!", "munch munch!", "so tasty!", "great job!",
        "wow!", "you got it!", "delicious!",
    ]

    func words(for speech: Speech) -> [Part] {
        switch speech {
        case .newNote:
            return [Part(text: "here's a new one!")]
        case .letter(let letter):
            return [letterPart(letter), Part(text: "!")]
        case .letters(let letters):
            var parts: [Part] = []
            for (i, letter) in letters.enumerated() {
                if i > 0 { parts.append(Part(text: ", ")) }
                parts.append(letterPart(letter))
            }
            parts.append(Part(text: "!"))
            return parts
        case .almost(let played, let expected):
            var parts = [Part(text: "that's a "), letterPart(played.naturalLetter), Part(text: "! ")]
            if expected == .middleC {
                parts.append(Part(text: "this one is the middle C"))
            } else if expected > played {
                parts.append(Part(text: "this one is higher up"))
            } else {
                parts.append(Part(text: "this one is lower down"))
            }
            return parts
        case .praise:
            let choices = Self.praise.filter { $0 != lastPraise }
            let phrase = choices.randomElement() ?? "yum!"
            lastPraise = phrase
            return [Part(text: phrase)]
        case .holdLonger:
            return [Part(text: "hold this one longer")]
        case .turnOnPiano:
            return [Part(text: "can you turn on the piano?")]
        case .sessionDone:
            return [Part(text: "look who ate well today!")]
        }
    }

    private func letterPart(_ letter: Letter) -> Part {
        let ipa: String = switch letter {
        case .a: "ˈeɪ"
        case .b: "ˈbiː"
        case .c: "ˈsiː"
        case .d: "ˈdiː"
        case .e: "ˈiː"
        case .f: "ˈɛf"
        case .g: "ˈdʒiː"
        }
        return Part(text: letter.name, ipa: ipa)
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
