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
                        MuncherLane(controller: controller, reserved: ListenButton.room)
                            .frame(width: laneWidth(screen: proxy.size.width))
                            .overlay(alignment: .bottom) {
                                ListenButton(controller: controller).padding(.bottom, 30)
                            }
                    }
                } else {
                    VStack(spacing: 0) {
                        staffColumn(height: proxy.size.height * 0.8)
                        MuncherLane(controller: controller, reserved: ListenButton.room)
                            .frame(height: proxy.size.height * 0.2)
                            .overlay(alignment: .trailing) {
                                ListenButton(controller: controller).padding(.trailing, 30)
                            }
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

    /// The lane takes the room the staff doesn't need at its full line gap, up to 30%
    /// of the width, so the munchers are big wherever there's room. The staff never
    /// shrinks for them. With real bars (2 at most) every lesson fits at 30pt on the 11
    /// inch: levels 1-2 get 27-30%, level 3 23-26%, level 4 26-27%, level 5 17-20%.
    private func laneWidth(screen width: CGFloat) -> CGFloat {
        let staff = CGFloat(controller.spec.width) * Metrics.gap * CGFloat(style.size) + 16
        return max(180, min(width * 0.3, max(width * 0.17, width - staff)))
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

/// Under the staff: the keyboard picture when a key is lit (hint 2, intros, "almost") or
/// while the screen is played to him with its keys lighting up, and a small ear picture
/// while the app plays the right pitch (hint 1).
struct HintBand: View {
    let controller: PracticeController
    @State private var showEar = false

    var body: some View {
        ZStack {
            if let playing = controller.playingKeys {
                KeyboardPicture(range: controller.keyboardRange, lit: playing)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .transition(.opacity)
            } else if !controller.session.keyboardHint.isEmpty {
                // a new note's intro: its letter on the lit key, so he learns its name
                KeyboardPicture(range: controller.keyboardRange, lit: controller.session.keyboardHint,
                                letters: controller.session.introNote != nil)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .transition(.opacity)
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
        .animation(.easeInOut(duration: 0.25), value: controller.playingKeys == nil)
        .animation(.easeInOut(duration: 0.25), value: showEar)
        .task(id: controller.soundHintAt) {
            guard controller.soundHintAt != nil else { return }
            showEar = true
            try? await Task.sleep(for: .seconds(1.6 * controller.timeScale))
            showEar = false
        }
    }
}

/// The play button, on every screen, at the foot of the munchers' lane away from the
/// staff. Picture only. Tapping it plays the screen with the keyboard lighting up; it
/// fades back while something is playing or there's nothing to play.
struct ListenButton: View {
    let enabled: Bool
    let action: () -> Void

    static let size: CGFloat = 96
    /// Room the lane keeps clear for it, so a muncher never sits under it.
    static let room: CGFloat = size + 46

    init(enabled: Bool, action: @escaping () -> Void) {
        self.enabled = enabled
        self.action = action
    }

    init(controller: PracticeController) {
        self.init(enabled: controller.canListen, action: controller.listen)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Theme.button)
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                Image(systemName: "play.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: 4) // the triangle's weight sits left of its box
            }
            .frame(width: Self.size, height: Self.size)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .animation(.easeInOut(duration: 0.2), value: enabled)
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
