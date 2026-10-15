import Foundation
import NoteCore
import Observation

enum InputSignal: Sendable {
    case note(NoteEvent)
    /// A piano showed up or went away.
    case connection(Bool)
}

/// Where every key press comes in: CoreMIDI, the DEBUG on-screen keyboard and the
/// DEBUG demo script all go through `emit`, so the practice screen can't tell them apart.
/// Each listener (practice screen, MIDI monitor) gets its own stream.
@MainActor @Observable
final class InputHub {
    /// Names of the MIDI sources that are connected right now.
    private(set) var midiSources: [String] = []

    /// DEBUG on-screen keyboard. Counts as a piano while it's on.
    var debugKeyboardOn = false {
        didSet { publishConnection() }
    }

    /// DEBUG demo script: forces connected / disconnected. nil = real state.
    var demoConnected: Bool? {
        didSet { publishConnection() }
    }

    var isConnected: Bool {
        demoConnected ?? (!midiSources.isEmpty || debugKeyboardOn)
    }

    @ObservationIgnored private var listeners: [UUID: AsyncStream<InputSignal>.Continuation] = [:]
    @ObservationIgnored private var lastConnected = false
    @ObservationIgnored private var midi: MIDIInput?

    init() {}

    /// Starts listening to CoreMIDI. Safe to skip (previews, demo runs).
    func startMIDI() {
        guard midi == nil else { return }
        lastConnected = isConnected
        midi = MIDIInput(
            onEvent: { [weak self] event in self?.emit(event) },
            onSourcesChanged: { [weak self] names in self?.sourcesChanged(names) }
        )
        midi?.start()
    }

    func signals() -> AsyncStream<InputSignal> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<InputSignal>.makeStream(bufferingPolicy: .unbounded)
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.listeners[id] = nil }
        }
        listeners[id] = continuation
        return stream
    }

    /// DEBUG: print every event and source change (checking MIDI without a screen).
    var logs = false

    func emit(_ event: NoteEvent) {
        if logs { print("input: \(event.pitch.name) \(event.kind.rawValue) velocity \(event.velocity)") }
        broadcast(.note(event))
    }

    private func sourcesChanged(_ names: [String]) {
        if logs { print("input: sources \(names)") }
        midiSources = names
        publishConnection()
    }

    private func publishConnection() {
        let connected = isConnected
        guard connected != lastConnected else { return }
        lastConnected = connected
        broadcast(.connection(connected))
    }

    private func broadcast(_ signal: InputSignal) {
        for continuation in listeners.values {
            continuation.yield(signal)
        }
    }
}
