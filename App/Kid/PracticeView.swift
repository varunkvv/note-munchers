import NoteCore
import SwiftUI

/// The practice screen. The staff gets most of the room. The keyboard picture has
/// its own band under it, and the munchers live in a lane off to the side, so all the
/// movement happens away from the staff.
struct PracticeView: View {
    let controller: PracticeController
    let input: InputHub
    /// The "done for now" door: he can always stop, and it ends kindly.
    let onDone: () -> Void

    @AppStorage(StaffStyle.Key.size) private var staffSize = StaffStyle().size
    @AppStorage(StaffStyle.Key.lineThickness) private var lineThickness = StaffStyle().lineThickness
    @AppStorage(StaffStyle.Key.spaceTint) private var spaceTint = StaffStyle().spaceTint
    @Environment(\.colorSchemeContrast) private var contrast

    private var style: StaffStyle {
        StaffStyle(size: staffSize, lineThickness: lineThickness, spaceTint: spaceTint, highContrast: contrast == .increased)
            .clamped
    }

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width >= proxy.size.height
            ZStack {
                style.paper.ignoresSafeArea()
                if landscape {
                    HStack(spacing: 0) {
                        staffColumn(height: proxy.size.height)
                        MuncherLane(controller: controller)
                            .frame(width: max(180, proxy.size.width * 0.17))
                    }
                } else {
                    VStack(spacing: 0) {
                        staffColumn(height: proxy.size.height * 0.8)
                        MuncherLane(controller: controller)
                            .frame(height: proxy.size.height * 0.2)
                    }
                }
            }
        }
        .overlay {
            if let id = controller.hatchQueue.first {
                HatchView(controller: controller, id: id)
                    .id(id)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: controller.hatchQueue.first)
        .overlay {
            if controller.isPaused {
                TurnOnPianoView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: controller.isPaused)
        .overlay(alignment: .topTrailing) {
            DoneForNowButton(action: onDone)
        }
        #if DEBUG
        .overlay(alignment: .bottom) {
            if input.debugKeyboardOn {
                DebugKeyboard(input: input, range: controller.keyboardRange)
            }
        }
        #endif
    }

    private func staffColumn(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            StaffView(
                spec: controller.spec, item: controller.item, doneCount: controller.doneCount,
                effects: controller.effects, style: style, gap: Metrics.gap * CGFloat(style.size)
            )
            .padding(.horizontal, 8)
            .padding(.top, 12)
            HintBand(controller: controller)
                .frame(height: height * 0.21)
        }
    }
}

/// Under the staff: the keyboard picture when a key is lit (hint 2, intros, "almost"),
/// and a small ear picture while the app plays the right pitch (hint 1).
struct HintBand: View {
    let controller: PracticeController
    @State private var showEar = false

    var body: some View {
        ZStack {
            if !controller.session.keyboardHint.isEmpty {
                KeyboardPicture(range: controller.keyboardRange, lit: controller.session.keyboardHint)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .transition(.opacity)
            }
            if controller.item?.isRhythm == true {
                // sound before symbol: he can hear the line again whenever he wants
                Button(action: controller.playPhrase) {
                    Image(systemName: "speaker.wave.2.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Theme.button)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 28)
            }
            if showEar {
                Image(systemName: "ear.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Theme.keyLit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 28)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controller.session.keyboardHint)
        .animation(.easeInOut(duration: 0.25), value: showEar)
        .task(id: controller.soundHintAt) {
            guard controller.soundHintAt != nil else { return }
            showEar = true
            try? await Task.sleep(for: .seconds(1.6 * controller.timeScale))
            showEar = false
        }
    }
}

/// Always on the practice screen, in the munchers' corner away from the staff.
/// Big enough for a 6 year old. One tap ends the session kindly (end screen).
struct DoneForNowButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.62, green: 0.48, blue: 0.85))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                Image(systemName: "door.left.hand.open")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 78, height: 78)
        }
        .buttonStyle(.plain)
        .padding(20)
    }
}
