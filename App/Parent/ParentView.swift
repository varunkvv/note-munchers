import NoteCore
import SwiftUI

/// The parent area, behind the 3 second hold. Text is fine here.
struct ParentView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section("Piano") {
                    NavigationLink("MIDI monitor", value: "monitor")
                    LabeledContent("Status", value: model.input.isConnected ? "Connected" : "No MIDI source")
                }
                #if DEBUG
                Section("Debug") {
                    Toggle("On-screen keyboard", isOn: Binding(
                        get: { model.input.debugKeyboardOn },
                        set: { model.input.debugKeyboardOn = $0 }
                    ))
                }
                #endif
            }
            .navigationTitle("Parents")
            .navigationDestination(for: String.self) { page in
                switch page {
                case "monitor": MIDIMonitorView(input: model.input)
                default: EmptyView()
                }
            }
            .onAppear {
                if let page = model.parentPage {
                    path = [page]
                    model.parentPage = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 640)
        #endif
    }
}
