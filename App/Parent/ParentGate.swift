import SwiftUI

/// A small grey button that only works when held for 3 seconds, so a 6 year old
/// doesn't wander into the parent area. A ring fills while it's held.
struct ParentGate: View {
    var symbol = "gearshape.fill"
    let action: () -> Void

    @State private var pressing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.parentIcon.opacity(0.25), lineWidth: 4)
            Circle()
                .trim(from: 0, to: pressing ? 1 : 0)
                .stroke(Theme.parentIcon, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.parentIcon.opacity(0.8))
        }
        .frame(width: 46, height: 46)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 3) {
            pressing = false
            action()
        } onPressingChanged: { isPressing in
            withAnimation(isPressing ? .linear(duration: 3) : .easeOut(duration: 0.2)) {
                pressing = isPressing
            }
        }
        .padding(16)
    }
}
