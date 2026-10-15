#if DEBUG
import NoteCore
import SwiftUI

/// DEBUG builds only: a tappable keyboard strip for the simulator and the mac without
/// a piano. Sends through `InputHub.emit`, the same path as CoreMIDI. Grey so it
/// never looks like part of the kid's screen.
struct DebugKeyboard: View {
    let input: InputHub
    let range: ClosedRange<Pitch>

    var body: some View {
        KeyboardPicture(
            range: range, litColor: .gray,
            onPress: { input.emit(.on($0, at: HostClock.now)) },
            onRelease: { input.emit(.off($0, at: HostClock.now)) }
        )
        .frame(height: 120)
        .padding(10)
        .background(Color.gray.opacity(0.35))
    }
}
#endif
