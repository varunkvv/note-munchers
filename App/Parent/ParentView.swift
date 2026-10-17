import Charts
import NoteCore
import SwiftUI

/// The parent area, behind the parent gate. Text is fine here.
struct ParentView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []
    @State private var trends = Trends(samples: [])
    @State private var sessions: [SessionRecord] = []
    @State private var celebrate = ""

    @AppStorage(StaffStyle.Key.size) private var staffSize = StaffStyle().size
    @AppStorage(StaffStyle.Key.lineThickness) private var lineThickness = StaffStyle().lineThickness
    @AppStorage(StaffStyle.Key.spaceTint) private var spaceTint = StaffStyle().spaceTint
    @AppStorage(IntroCards.seenKey) private var introSeen = false

    private var engine: MasteryEngine { model.engine }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { scroller in
            Form {
                if model.store.isTemporary {
                    Section {
                        Label("Progress can't be saved on this device right now. It will be lost when the app closes.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                Section("Celebrate together") {
                    Label(celebrate, systemImage: "hands.clap.fill")
                        .foregroundStyle(.primary)
                }
                progressSection
                levelSection.id("levels")
                notesSection
                sessionSection.id("session")
                staffSection.id("staff")
                Section("Piano") {
                    NavigationLink("MIDI monitor", value: "monitor")
                    LabeledContent("Status", value: model.input.isConnected ? "Connected" : "No MIDI source")
                }
                Section {
                    Button("Show the intro again") {
                        introSeen = false
                        dismiss()
                    }
                } footer: {
                    Text("The three picture cards that explain the game. They stay on the home screen until he taps \"Let's go!\".")
                }
                historySection.id("history")
                Section("Credits") {
                    Text("Song time's piano: Salamander Grand Piano by Alexander Holm, CC BY 3.0 (creativecommons.org/licenses/by/3.0). Music symbols: Bravura, SIL Open Font License.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            .onAppear {
                // DEBUG demo deep link: "#units", "#staff", "#history"
                if let page = model.parentPage, page.hasPrefix("#") {
                    model.parentPage = nil
                    Task {
                        try? await Task.sleep(for: .seconds(0.5))
                        scroller.scrollTo(String(page.dropFirst()), anchor: .top)
                    }
                }
            }
            }
            .navigationTitle("Parents")
            .navigationDestination(for: String.self) { page in
                if page == "monitor" {
                    MIDIMonitorView(input: model.input)
                } else if page == "levels" {
                    LevelsView(model: model)
                } else if let item = trends.items[page] ?? emptyItem(page) {
                    ItemDetailView(id: page, trend: item, progress: engine.progress(for: page), habit: NoteKey(id: page).map(engine.habit))
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                reload()
                if let page = model.parentPage, !page.hasPrefix("#") {
                    path = [page]
                    model.parentPage = nil
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 680, minHeight: 720)
        #endif
    }

    private func reload() {
        let records = model.store.attempts(since: Date().addingTimeInterval(-60 * 86_400))
        trends = Trends(records: records)
        sessions = model.store.sessions(limit: 30)
        celebrate = Celebration.suggest(engine: engine, trends: trends, records: model.store.attempts(), sessions: sessions)
    }

    private func emptyItem(_ id: ItemID) -> Trends.Item? {
        NoteKey(id: id) == nil ? nil : Trends.Item(id: id, thisWeek: .init(), lastWeek: .init(), days: [])
    }

    // MARK: sections

    private var progressSection: some View {
        Section("This week") {
            LabeledContent("Notes in play", value: "\(engine.pool.count)")
            let played = engine.allProgress.map(\.key)
            if !played.isEmpty {
                LabeledContent("Notes that are a habit", value: "\(played.filter(engine.isHabit).count) of \(played.count)")
            }
            LabeledContent("Notes per screen", value: "\(engine.screenSize)")
            let week = sessions.filter { $0.startedAt > Date().addingTimeInterval(-7 * 86_400) }
            LabeledContent("Sessions", value: "\(week.count), \(Int((week.map(\.activeDuration).reduce(0, +) / 60).rounded())) min")
            if let rate = trends.thisWeek.firstTryRate {
                let before = trends.lastWeek.firstTryRate.map { ", last week \(Self.percent($0))" } ?? ""
                LabeledContent("Right first try", value: "\(Self.percent(rate))\(before)")
            }
            if let median = trends.thisWeek.median {
                let before = trends.lastWeek.median.map { String(format: ", last week %.1f s", $0) } ?? ""
                LabeledContent("Typical time to find a note", value: String(format: "%.1f s", median) + before)
            }
        }
    }

    private var notesSection: some View {
        Section {
            if engine.allProgress.isEmpty {
                Text("Nothing played yet.").foregroundStyle(.secondary)
            }
            ForEach(engine.allProgress) { progress in
                NavigationLink(value: progress.id) {
                    NoteRow(progress: progress, trend: trends.items[progress.id], isHabit: engine.isHabit(progress.key))
                }
            }
        } header: {
            Text("Notes")
        } footer: {
            Text("Box 1-5 goes up after a right-first-try answer and down after a miss. Right first try and time are over his last 8 tries. Solid means the next note can unlock. Habit means it's automatic: quick and steady from one note to the next, right first try on two different days. Each level's last lesson waits for it.")
        }
    }

    private var levelSection: some View {
        Section {
            NavigationLink(value: "levels") {
                LabeledContent("Level \(engine.level.number): \(engine.level.title)", value: "lesson \(engine.lesson.id)")
            }
        } header: {
            Text("Level")
        } footer: {
            Text("\(engine.lesson.title). Pick a level, or jump to a lesson inside one.")
        }
    }

    private var sessionSection: some View {
        Section("Session length") {
            Stepper(value: Binding(
                get: { model.config.sessionMaxItems },
                set: { value in model.updateConfig { $0.sessionMaxItems = value } }
            ), in: 5...60, step: 5) {
                LabeledContent("Screens", value: "\(model.config.sessionMaxItems)")
            }
            Stepper(value: Binding(
                get: { Int(model.config.sessionMaxDuration / 60) },
                set: { value in model.updateConfig { $0.sessionMaxDuration = Double(value) * 60 } }
            ), in: 1...20) {
                LabeledContent("Minutes", value: "\(Int(model.config.sessionMaxDuration / 60))")
            }
            Text("A screen is the notes he reads in one go (1 to 8, growing as he gets faster). A session ends at whichever comes first, always between screens. Time with the piano off doesn't count.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var staffSection: some View {
        Section {
            VStack(alignment: .leading) {
                Text("Staff size")
                Slider(value: $staffSize, in: StaffStyle.sizeRange)
            }
            VStack(alignment: .leading) {
                Text("Line thickness")
                Slider(value: $lineThickness, in: StaffStyle.thicknessRange)
            }
            Toggle("Tint the spaces", isOn: $spaceTint)
            let preview = PracticeItem([Pitch(.g, 4), Pitch(.a, 4), Pitch(.b, 4)].map { WrittenNote(.treble, [$0]) })
            let style = StaffStyle(size: staffSize, lineThickness: lineThickness, spaceTint: spaceTint).clamped
            StaffView(spec: StaffSpec(item: preview), item: preview, style: style, gap: Metrics.gap * CGFloat(style.size))
            .frame(height: 300)
            .background(Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Button("Reset to defaults") {
                staffSize = StaffStyle().size
                lineThickness = StaffStyle().lineThickness
                spaceTint = StaffStyle().spaceTint
            }
        } header: {
            Text("Staff (vision)")
        } footer: {
            Text("Check from the piano bench: can he tell G, A and B apart (line, space, line) without leaning in? The preview is drawn at the real size. The same size is used in every lesson.")
        }
    }

    private var historySection: some View {
        Section("Recent sessions") {
            if sessions.isEmpty {
                Text("No sessions yet.").foregroundStyle(.secondary)
            }
            ForEach(sessions.prefix(12)) { session in
                HStack {
                    Text(session.startedAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    Spacer()
                    Text("\(session.itemsPlayed) notes") // notes since round 2, items before
                    Text(Self.percent(session.itemsPlayed > 0 ? Double(session.firstTryCount) / Double(session.itemsPlayed) : 0) + " first try")
                        .foregroundStyle(.secondary)
                    Text("\(max(1, Int((session.activeDuration / 60).rounded()))) min").foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

struct NoteRow: View {
    let progress: NoteProgress
    let trend: Trends.Item?
    var isHabit = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(ItemLabel.text(progress.id)).font(.body.monospaced().bold())
                    if progress.isSolid {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    }
                    if isHabit {
                        Text("habit")
                            .font(.caption.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.teal.opacity(0.18)))
                            .foregroundStyle(.teal)
                    }
                }
                HStack(spacing: 10) {
                    BoxDots(box: progress.box)
                    if let rate = progress.recentFirstTryRate {
                        Text("\(ParentView.percent(rate)) first try")
                    }
                    if let median = progress.medianResponse {
                        Text(String(format: "%.1f s", median))
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                if let trend, let change = Trends.speedChange(trend) {
                    Text(change.text)
                        .font(.footnote)
                        .foregroundStyle(change.better == true ? .green : change.better == false ? .orange : .secondary)
                }
            }
            Spacer()
            if let days = trend?.days, days.count > 1 {
                Chart(days) { day in
                    LineMark(x: .value("Day", day.date), y: .value("Seconds", day.median))
                        .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(width: 110, height: 36)
            }
        }
    }
}

struct BoxDots: View {
    let box: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(i <= box ? Color.green : Color.secondary.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityLabel("box \(box) of 5")
    }
}

struct LessonStatusBadge: View {
    let status: LessonStatus

    var body: some View {
        let (text, color): (String, Color) = switch status {
        case .completed: ("done", .green)
        case .current: ("now", .blue)
        case .skipped: ("skipped", .orange)
        case .upcoming: ("", .secondary)
        }
        if !text.isEmpty {
            Text(text)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(color.opacity(0.15)))
                .foregroundStyle(color)
        }
    }
}

struct ItemDetailView: View {
    let id: ItemID
    let trend: Trends.Item
    let progress: NoteProgress?
    var habit: HabitProgress?

    var body: some View {
        Form {
            if let key = NoteKey(id: id) {
                NoteStaff(key: key)
                    .frame(height: 160)
                    .background(Theme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if let progress {
                Section("Now") {
                    LabeledContent("Box", value: "\(progress.box) of 5")
                    LabeledContent("Solid", value: progress.isSolid ? "yes" : "not yet")
                    LabeledContent("Times played", value: "\(progress.attempts)")
                    if let rate = progress.recentFirstTryRate {
                        LabeledContent("Right first try (last 8)", value: ParentView.percent(rate))
                    }
                    if let median = progress.medianResponse {
                        LabeledContent("Typical time (last 8)", value: String(format: "%.1f s", median))
                    }
                    if let change = Trends.speedChange(trend) {
                        LabeledContent("Speed", value: change.text)
                    }
                }
            }
            if let habit {
                Section {
                    let config = NoteCoreConfig.default
                    LabeledContent("Habit", value: habit.isHabit ? "yes" : "not yet (\(Int((habit.fraction * 100).rounded()))% of the way)")
                    LabeledContent("Plays mid-screen", value: "\(habit.samples) (needs \(config.habitWindow))")
                    if habit.samples > 0 {
                        LabeledContent("Right first try", value: "\(habit.firstTries) of \(habit.samples) (needs \(config.habitFirstTry) of \(config.habitWindow))")
                    }
                    if let median = habit.median {
                        LabeledContent("Typical time from the note before", value: String(format: "%.1f s (under %.0f s)", median, config.habitMedian))
                    }
                    if let steadiness = habit.steadiness {
                        let word = steadiness < config.habitCV ? "steady" : "still varies"
                        LabeledContent("Steadiness", value: String(format: "%@ (%.2f, under %.1f)", word, steadiness, config.habitCV))
                    }
                    LabeledContent("Right first try at its first showing", value: "\(habit.cleanDays) of the last \(config.habitDays) days")
                } header: {
                    Text("Habit")
                } footer: {
                    Text("Knowing a note isn't the same as it being automatic. Habit looks at the times between notes in the middle of a screen, not the first note (that one includes taking in a new screen): fast, steady, right first try, and on two different days. Used to pick which notes the pattern screens practise and to finish each level's last lesson. It never holds back a new note.")
                }
            }
            if trend.days.count > 0 {
                Section("Time to find it, per day") {
                    Chart(trend.days) { day in
                        LineMark(x: .value("Day", day.date, unit: .day), y: .value("Seconds", day.median))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Day", day.date, unit: .day), y: .value("Seconds", day.median))
                    }
                    .chartYAxisLabel("seconds")
                    .frame(height: 200)
                }
                Section("Right first try, per day") {
                    Chart(trend.days) { day in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Right first try", day.firstTryRate * 100))
                            .foregroundStyle(.green.opacity(0.7))
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxisLabel("%")
                    .frame(height: 160)
                }
            }
        }
        .navigationTitle(ItemLabel.text(id))
    }
}

/// Levels 1-5 and the lessons inside each. The parent picks a level, or jumps to a
/// lesson inside one. Lessons move on by themselves as he masters them.
struct LevelsView: View {
    let model: AppModel
    @State private var level = 1
    @State private var pending: Lesson?

    private var engine: MasteryEngine { model.engine }

    var body: some View {
        Form {
            Section {
                Picker("Level", selection: $level) {
                    ForEach(engine.curriculum.levels) { level in
                        Text("\(level.number)").tag(level.number)
                    }
                }
                .pickerStyle(.segmented)
                if let current = engine.curriculum.level(level) {
                    HStack {
                        Text("Level \(current.number): \(current.title)").font(.headline)
                        Spacer()
                        LessonStatusBadge(status: engine.status(ofLevel: current.number))
                    }
                    if engine.lesson.level != current.number {
                        Button("Start level \(current.number)") { model.moveToLevel(current.number) }
                    }
                }
            }
            if let current = engine.curriculum.level(level) {
                Section {
                    ForEach(current.lessons) { lesson in
                        Button {
                            if lesson.id != engine.lesson.id { pending = lesson }
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(lesson.id)  \(lesson.title)").foregroundStyle(.primary)
                                    Text(Self.detail(lesson)).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                LessonStatusBadge(status: engine.status(ofLesson: lesson.id))
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text("Lessons")
                } footer: {
                    Text("Tap a lesson to jump there. Every session mixes treble and bass, and has a short burst of patterns (runs, motifs, echoes) on notes he has met. Each level ends with a lesson of only patterns.")
                }
            }
        }
        .navigationTitle("Level and lesson")
        .onAppear { level = engine.lesson.level }
        .confirmationDialog(
            pending.map { "Move to lesson \($0.id)?" } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            if let lesson = pending {
                Button("Move to \(lesson.id) \(lesson.title.lowercased())") { model.moveToLesson(lesson.id) }
            }
        } message: {
            Text("Lessons in between aren't marked done. Going back means he plays that lesson until it's solid again, then moves on to the first lesson that isn't done.")
        }
    }

    static func drillName(_ drill: Drill) -> String {
        switch drill {
        case .run: "runs"
        case .motif: "motifs"
        case .home: "home note"
        case .repeatNote: "repeats"
        case .echo: "echoes"
        case .shift: "position shifts"
        case .movedTwo: "two at once moved"
        case .brokenTwo: "broken then together"
        case .rhythmMotif: "rhythm motifs"
        case .tune: "bits of tunes"
        }
    }

    /// "treble focus, 2-3 notes a screen, new: E5 G5"
    static func detail(_ lesson: Lesson) -> String {
        let focus = switch lesson.focus {
        case .treble: "more treble"
        case .bass: "more bass"
        case .both: "both clefs"
        }
        let staff = lesson.layout == .grand ? ", grand staff" : ""
        let sizes = lesson.sizes.count == 1 ? "\(lesson.sizes.lowerBound)" : "\(lesson.sizes.lowerBound)-\(lesson.sizes.upperBound)"
        let new = lesson.newKeys.map(\.pitch.name)
        var notes = new.isEmpty ? "practice" : "new: " + new.joined(separator: " ")
        if lesson.isDrillLesson {
            notes = "patterns: \(lesson.drills.map(Self.drillName).joined(separator: ", ")), done when his notes are a habit on two days"
        }
        let key = lesson.keySignature == .gMajor ? ", G major" : ""
        return "\(focus)\(staff), \(sizes) notes a screen\(key), \(notes)"
    }
}
