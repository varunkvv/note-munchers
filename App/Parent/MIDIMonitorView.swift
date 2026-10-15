import NoteCore
import SwiftUI

/// Live key presses with their names, to check the piano is talking to the app
/// (plan: "MIDI monitor names 10 keys across the range correctly").
struct MIDIMonitorView: View {
    let input: InputHub

    struct Row: Identifiable {
        let id = UUID()
        let event: NoteEvent
        let received: Date
    }

    @State private var rows: [Row] = []

    var body: some View {
        List {
            Section("Sources") {
                if input.midiSources.isEmpty {
                    Text("No MIDI source. Is the piano on and the cable plugged in?")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(input.midiSources, id: \.self) { Text($0) }
                }
                #if DEBUG
                if input.debugKeyboardOn { Text("Debug on-screen keyboard") }
                #endif
            }
            Section("Keys pressed (newest first)") {
                if rows.isEmpty {
                    Text("Play a few keys").foregroundStyle(.secondary)
                }
                ForEach(rows.reversed()) { row in
                    HStack(spacing: 16) {
                        Text(row.event.pitch.name)
                            .font(.title2.monospaced().bold())
                            .frame(width: 70, alignment: .leading)
                        if row.event.pitch == .middleC {
                            Text("middle C").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("velocity \(row.event.velocity)").foregroundStyle(.secondary)
                        Text(row.received, format: .dateTime.hour().minute().second())
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("MIDI monitor")
        .task {
            for await signal in input.signals() {
                if case .note(let event) = signal, event.kind == .on {
                    rows.append(Row(event: event, received: Date()))
                    if rows.count > 60 { rows.removeFirst(rows.count - 60) }
                }
            }
        }
    }
}
