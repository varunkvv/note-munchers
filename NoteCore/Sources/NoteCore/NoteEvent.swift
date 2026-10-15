/// A key going down or up on the piano.
///
/// `time` is seconds on one monotonic clock that the app also uses for every other
/// call into NoteCore (start, tick, next, connect/disconnect). NoteCore never reads
/// a clock itself.
public struct NoteEvent: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case on, off
    }

    public var kind: Kind
    public var pitch: Pitch
    public var velocity: Int
    public var time: Double

    public init(_ kind: Kind, _ pitch: Pitch, velocity: Int = 64, at time: Double) {
        self.kind = kind
        self.pitch = pitch
        self.velocity = velocity
        self.time = time
    }

    public static func on(_ pitch: Pitch, velocity: Int = 64, at time: Double) -> NoteEvent {
        NoteEvent(.on, pitch, velocity: velocity, at: time)
    }

    public static func off(_ pitch: Pitch, at time: Double) -> NoteEvent {
        NoteEvent(.off, pitch, velocity: 0, at: time)
    }

    /// Parses a MIDI 1.0 channel message (status byte + two data bytes).
    /// Note-on with velocity 0 is a note-off. Anything that isn't note-on/off returns nil.
    public init?(status: UInt8, data1: UInt8, data2: UInt8, at time: Double) {
        let type = status & 0xF0
        let note = Int(data1 & 0x7F)
        let velocity = Int(data2 & 0x7F)
        switch type {
        case 0x90 where velocity > 0:
            self.init(.on, Pitch(midi: note), velocity: velocity, at: time)
        case 0x90, 0x80:
            self.init(.off, Pitch(midi: note), velocity: 0, at: time)
        default:
            return nil
        }
    }

    /// Parses one 32-bit Universal MIDI Packet word holding a MIDI 1.0 channel voice
    /// message (message type 0x2), which is what `MIDIEventList` delivers for
    /// `._1_0` protocol input. Returns nil for every other message.
    public init?(umpWord word: UInt32, at time: Double) {
        guard word >> 28 == 0x2 else { return nil }
        self.init(
            status: UInt8((word >> 16) & 0xFF),
            data1: UInt8((word >> 8) & 0xFF),
            data2: UInt8(word & 0xFF),
            at: time
        )
    }
}
