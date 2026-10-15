import Charts
import NoteCore
import SwiftUI

/// The parent area, behind the 3 second hold. Text is fine here.
struct ParentView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []
    @State private var trends = Trends(samples: [])
    @State private var sessions: [SessionRecord] = []
    @State private var pendingUnit: Int?

    @AppStorage(StaffStyle.Key.size) private var staffSize = StaffStyle().size
    @AppStorage(StaffStyle.Key.lineThickness) private var lineThickness = StaffStyle().lineThickness
    @AppStorage(StaffStyle.Key.spaceTint) private var spaceTint = StaffStyle().spaceTint

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
                progressSection
                notesSection
                unitSection.id("units")
                sessionSection.id("session")
                staffSection.id("staff")
                Section("Piano") {
                    NavigationLink("MIDI monitor", value: "monitor")
                    LabeledContent("Status", value: model.input.isConnected ? "Connected" : "No MIDI source")
                }
                historySection.id("history")
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
                } else if let item = trends.items[page] ?? emptyItem(page) {
                    ItemDetailView(id: page, trend: item, progress: engine.progress(for: page))
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
            .confirmationDialog(
                pendingUnit.map { "Move to unit \($0)?" } ?? "",
                isPresented: Binding(get: { pendingUnit != nil }, set: { if !$0 { pendingUnit = nil } }),
                titleVisibility: .visible
            ) {
                if let number = pendingUnit {
                    Button("Move to unit \(number)") { model.moveToUnit(number) }
                }
            } message: {
                Text("Skipping ahead doesn't mark the units in between as done. Going back means he plays that unit until it's solid again, then returns to where he was.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 680, minHeight: 720)
        #endif
    }

    private func reload() {
        trends = Trends(records: model.store.attempts(since: Date().addingTimeInterval(-60 * 86_400)))
        sessions = model.store.sessions(limit: 12)
    }

    private func emptyItem(_ id: ItemID) -> Trends.Item? {
        Curriculum.standard.item(id) == nil ? nil : Trends.Item(id: id, thisWeek: .init(), lastWeek: .init(), days: [])
    }

    // MARK: sections

    private var progressSection: some View {
        Section("This week") {
            LabeledContent("Unit", value: "\(engine.unit.number) of \(engine.curriculum.units.count): \(engine.unit.title)")
            LabeledContent("Notes in play", value: "\(engine.pool.count)")
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
                    NoteRow(progress: progress, trend: trends.items[progress.id])
                }
            }
        } header: {
            Text("Notes")
        } footer: {
            Text("Box 1-5 goes up after a right-first-try answer and down after a miss. Right first try and time are over his last 8 tries. Solid means the next note can unlock.")
        }
    }

    private var unitSection: some View {
        Section {
            HStack {
                Button("Back one unit") { pendingUnit = max(1, engine.unit.number - 1) }
                    .disabled(engine.unit.number <= 1)
                Spacer()
                Button("Skip ahead one unit") { pendingUnit = min(engine.curriculum.units.count, engine.unit.number + 1) }
                    .disabled(engine.unit.number >= engine.curriculum.units.count)
            }
            .buttonStyle(.borderless)
            ForEach(engine.curriculum.units) { unit in
                Button {
                    if unit.number != engine.unit.number { pendingUnit = unit.number }
                } label: {
                    HStack {
                        Text("\(unit.number). \(unit.title)").foregroundStyle(.primary)
                        Spacer()
                        UnitStatusBadge(status: engine.status(ofUnit: unit.number))
                    }
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("Units")
        } footer: {
            Text("Tap a unit to move there. The app moves on by itself when he's solid.")
        }
    }

    private var sessionSection: some View {
        Section("Session length") {
            Stepper(value: Binding(
                get: { model.config.sessionMaxItems },
                set: { value in model.updateConfig { $0.sessionMaxItems = value } }
            ), in: 5...60, step: 5) {
                LabeledContent("Notes", value: "\(model.config.sessionMaxItems)")
            }
            Stepper(value: Binding(
                get: { Int(model.config.sessionMaxDuration / 60) },
                set: { value in model.updateConfig { $0.sessionMaxDuration = Double(value) * 60 } }
            ), in: 1...20) {
                LabeledContent("Minutes", value: "\(Int(model.config.sessionMaxDuration / 60))")
            }
            Text("A session ends at whichever comes first, always between notes. Time with the piano off doesn't count.")
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
            let preview = PracticeItem(.treble, [WrittenNote([Pitch(.c, 4)]), WrittenNote([Pitch(.d, 4)]), WrittenNote([Pitch(.e, 4)])])
            StaffView(
                spec: StaffSpec(items: [preview], layout: .treble), item: preview,
                style: StaffStyle(size: staffSize, lineThickness: lineThickness, spaceTint: spaceTint)
            )
            .frame(height: 220)
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
            Text("Check from the piano bench: can he tell C, D and E apart (ledger line, space below, bottom line) without leaning in? Size is relative to the biggest staff that fits the screen.")
        }
    }

    private var historySection: some View {
        Section("Recent sessions") {
            if sessions.isEmpty {
                Text("No sessions yet.").foregroundStyle(.secondary)
            }
            ForEach(sessions) { session in
                HStack {
                    Text(session.startedAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    Spacer()
                    Text("\(session.itemsPlayed) notes")
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

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(ItemLabel.text(progress.id)).font(.body.monospaced().bold())
                    if progress.isSolid {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
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

struct UnitStatusBadge: View {
    let status: UnitStatus

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

    var body: some View {
        Form {
            if let item = Curriculum.standard.item(id) {
                StaffView(spec: StaffSpec(items: [item], layout: item.clef == .treble ? .treble : .bass), item: item)
                    .frame(height: 160)
                    .background(Theme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if let progress {
                Section("Now") {
                    LabeledContent("Box", value: "\(progress.box) of 5")
                    if let rhythmBox = progress.rhythmBox {
                        LabeledContent("Rhythm box", value: "\(rhythmBox) of 5")
                    }
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
