import CoreMIDI
import Foundation
import NoteCore

/// CoreMIDI input from every source, with hot-plug.
///
/// The read block runs on a CoreMIDI thread. It turns each packet into `NoteEvent`s
/// there (with the packet's own timestamp, so the hop to main adds no judging error)
/// and hands them to main in order.
final class MIDIInput {
    private let onEvent: @MainActor (NoteEvent) -> Void
    private let onSourcesChanged: @MainActor ([String]) -> Void

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var connected: Set<MIDIEndpointRef> = []

    init(onEvent: @escaping @MainActor (NoteEvent) -> Void, onSourcesChanged: @escaping @MainActor ([String]) -> Void) {
        self.onEvent = onEvent
        self.onSourcesChanged = onSourcesChanged
    }

    deinit {
        if port != 0 { MIDIPortDispose(port) }
        if client != 0 { MIDIClientDispose(client) }
    }

    func start() {
        let clientStatus = MIDIClientCreateWithBlock("Note Munchers" as CFString, &client) { [weak self] notification in
            switch notification.pointee.messageID {
            case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved, .msgPropertyChanged:
                DispatchQueue.main.async { self?.connectSources() }
            default:
                break
            }
        }
        guard clientStatus == noErr else {
            print("MIDI: client create failed \(clientStatus)")
            return
        }
        let onEvent = self.onEvent
        let portStatus = MIDIInputPortCreateWithProtocol(client, "Piano In" as CFString, ._1_0, &port) { list, _ in
            for packet in list.unsafeSequence() {
                let stamp = packet.pointee.timeStamp
                // many sources send 0 for "now"
                let time = stamp == 0 ? HostClock.now : HostClock.seconds(hostTime: stamp)
                let events = NoteEvent.events(inUMPWords: packet.words(), at: time)
                guard !events.isEmpty else { continue }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        for event in events { onEvent(event) }
                    }
                }
            }
        }
        guard portStatus == noErr else {
            print("MIDI: input port create failed \(portStatus)")
            return
        }
        connectSources()
    }

    /// Connects every online source not connected yet and forgets the ones that went away.
    private func connectSources() {
        guard port != 0 else { return }
        var current: [MIDIEndpointRef] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(i)
            guard source != 0, !Self.isOffline(source) else { continue }
            current.append(source)
        }
        for source in current where !connected.contains(source) {
            if MIDIPortConnectSource(port, source, nil) == noErr {
                connected.insert(source)
            }
        }
        for source in connected where !current.contains(source) {
            MIDIPortDisconnectSource(port, source)
            connected.remove(source)
        }
        let names = current.filter(connected.contains).map(Self.name)
        MainActor.assumeIsolated { onSourcesChanged(names) }
    }

    private static func isOffline(_ endpoint: MIDIEndpointRef) -> Bool {
        var offline: Int32 = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline)
        return offline != 0
    }

    private static func name(_ endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr, let name {
            return name.takeRetainedValue() as String
        }
        return "MIDI source"
    }
}
