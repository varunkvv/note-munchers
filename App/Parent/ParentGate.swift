import SwiftUI

/// The way into the parent area. Tap the gear, then answer one times-table question in
/// a small panel. A 6 year old can't read it, a grown-up answers it in a second. A wrong
/// answer swaps in a new question. No long press.
struct ParentGate: View {
    var symbol = "gearshape.fill"
    let action: () -> Void

    @State private var asking = false
    /// answered right: run the action once the panel has gone
    @State private var passed = false

    var body: some View {
        Button {
            asking = true
        } label: {
            ZStack {
                Circle().fill(Theme.parentIcon.opacity(0.12))
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.parentIcon.opacity(0.8))
            }
            .frame(width: 46, height: 46)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Grown-up settings")
        .popover(isPresented: $asking, arrowEdge: .top) {
            ParentGateQuestion {
                passed = true
                asking = false
            } onCancel: {
                asking = false
            }
            .presentationCompactAdaptation(.popover)
            .presentationBackground(Theme.paper)
        }
        .onChange(of: asking) { _, isAsking in
            guard !isAsking, passed else { return }
            passed = false
            // the parent area is a sheet. presenting it while the popover is still
            // animating away fails on iPad, so wait for the popover to go first
            Task {
                try? await Task.sleep(for: .seconds(0.4))
                action()
            }
        }
        .padding(16)
        #if DEBUG
        .task {
            // -demoGate open|right|wrong: open the panel by itself (simctl can't tap)
            guard ParentGateQuestion.demo != nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            asking = true
        }
        #endif
    }
}

/// The question panel. Its own view so it can be drawn outside the popover too.
struct ParentGateQuestion: View {
    let onPass: () -> Void
    let onCancel: () -> Void

    @State private var question = Question.random()
    @State private var missed = false

    struct Question: Equatable {
        let a: Int
        let b: Int
        /// three answers, the right one somewhere among them
        let choices: [Int]

        var answer: Int { a * b }

        /// Single digit times single digit, never x1 or x2. The wrong answers are
        /// close by (a neighbour in the table, or a few off), so none of the three stands out.
        static func random(not previous: Question? = nil) -> Question {
            while true {
                let a = Int.random(in: 3...9)
                let b = Int.random(in: 3...9)
                if let previous, previous.a == a, previous.b == b { continue }
                let answer = a * b
                let near = Set([(a + 1) * b, (a - 1) * b, a * (b + 1), a * (b - 1), answer + 1, answer - 1, answer + 2, answer - 2, answer + 10, answer - 10])
                    .filter { $0 > 0 && $0 != answer }
                let wrong = near.shuffled().prefix(2)
                guard wrong.count == 2 else { continue }
                return Question(a: a, b: b, choices: ([answer] + wrong).shuffled())
            }
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("For grown-ups")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.parentIcon)
                Text("What is \(question.a) × \(question.b)?")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 12) {
                ForEach(question.choices, id: \.self) { choice in
                    Button {
                        answer(choice)
                    } label: {
                        Text("\(choice)")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                            .frame(width: 92, height: 68)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lane))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.keyEdge.opacity(0.18)))
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(missed ? "Not quite. Here's a new one." : " ")
                .font(.footnote)
                .foregroundStyle(Theme.parentIcon)
            Button("Cancel", action: onCancel)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.parentIcon)
                .buttonStyle(.plain)
                .frame(minWidth: 120, minHeight: 44)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 14)
        .frame(minWidth: 360)
        .background(Theme.paper)
        #if DEBUG
        .task {
            guard let demo = Self.demo, demo != "open" else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if demo == "wrong", let wrong = question.choices.first(where: { $0 != question.answer }) {
                answer(wrong)
            } else if demo == "right" {
                answer(question.answer)
            }
        }
        #endif
    }

    private func answer(_ choice: Int) {
        if choice == question.answer {
            onPass()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                question = Question.random(not: question)
                missed = true
            }
        }
    }

    #if DEBUG
    /// `-demoGate open|right|wrong`
    static var demo: String? { UserDefaults.standard.string(forKey: "demoGate") }
    #endif
}
