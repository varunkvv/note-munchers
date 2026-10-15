import NoteCore
import SwiftUI

/// The side lane on the practice screen. The munchers move in here, never on the staff.
struct MuncherLane: View {
    let controller: PracticeController

    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(Theme.lane)
            .padding(12)
    }
}
