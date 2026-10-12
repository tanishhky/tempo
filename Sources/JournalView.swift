import SwiftUI

/// Local view state as objects, for the same reason as the other views: no @State macro.
final class JournalUI: ObservableObject {
    @Published var day = Calendar.current.startOfDay(for: Date())
}

/// Typed text for one activity card. Saved on return, not on every keystroke, so the journal file stays small.
final class CardDraft: ObservableObject {
    @Published var note = ""
    @Published var newItem = ""
}

struct JournalView: View {
    @ObservedObject var journal: JournalStore
    @ObservedObject var activities: ActivityStore
    @StateObject private var ui = JournalUI()

    private var dayKey: String { DayKey.string(ui.day) }
    private var isToday: Bool { Calendar.current.isDateInToday(ui.day) }

    /// Activities with a checklist, plus any that already have an entry for the selected day.
    private var shown: [Activity] {
        activities.activities.filter { !$0.checklist.isEmpty || journal.entry(dayKey, $0.id) != nil }
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM yyyy"
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if shown.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(shown) { activity in
                            ActivityCard(activity: activity, date: dayKey, journal: journal,
                                         color: activities.color(activity.id))
                                .id("\(dayKey)-\(activity.id)")
                        }
                    }
                }
                progressSection
            }
            .padding(28)
        }
        .frame(width: 780, height: 820)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { journal.reload() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Journal").font(.system(size: 26, weight: .semibold, design: .rounded))
            Spacer()
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                .help("Previous day")
            Text(Self.dayFmt.string(from: ui.day))
                .font(.headline)
                .frame(minWidth: 230)
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .help("Next day")
                .disabled(isToday)
            if !isToday {
                Button("Today") { ui.day = Calendar.current.startOfDay(for: Date()) }
            }
        }
        .buttonStyle(.borderless)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Nothing to check off yet").font(.headline)
            Text("Give an activity a checklist in Settings, under Activities, and it appears here every day. "
                 + "Your AI assistant can also add entries through the Tempo MCP server.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    /// One heatmap per activity with a checklist. Each day shades by the share of its items done.
    private var progressSection: some View {
        let tracked = activities.activities.filter { !$0.checklist.isEmpty }
        return VStack(alignment: .leading, spacing: 14) {
            Text("Progress").font(.headline)
            ForEach(tracked) { activity in
                let color = activities.color(activity.id)
                VStack(alignment: .leading, spacing: 6) {
                    Text(activity.name).font(.callout.weight(.medium))
                    Heatmap(calendar: Calendar.current) { date in
                        let key = DayKey.string(date)
                        let entry = journal.entry(key, activity.id)
                        let fraction = entry?.fraction ?? 0
                        let tip = entry.map { "\(Self.dayFmt.string(from: date)): \($0.doneCount) of \($0.items.count) done" }
                            ?? "\(Self.dayFmt.string(from: date)): nothing logged"
                        return HeatCell(fill: Theme.progress(fraction, color: color), tip: tip)
                    }
                    HeatLegend(color: color)
                }
            }
            if tracked.isEmpty {
                Text("Activities with a checklist show their progress here.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func shift(_ days: Int) {
        let next = Calendar.current.date(byAdding: .day, value: days, to: ui.day) ?? ui.day
        ui.day = min(next, Calendar.current.startOfDay(for: Date()))
    }
}

/// One activity's checklist for one day. Every change writes one line to the journal.
private struct ActivityCard: View {
    let activity: Activity
    let date: String
    @ObservedObject var journal: JournalStore
    let color: Color
    @StateObject private var draft = CardDraft()

    private var stored: JournalEntry? { journal.entry(date, activity.id) }
    /// Items for the day: what was saved, or the activity's default checklist if nothing was saved yet.
    private var items: [ChecklistItem] {
        stored?.items ?? activity.checklist.map { ChecklistItem(text: $0, done: false) }
    }
    private var fraction: Double {
        items.isEmpty ? 0 : Double(items.filter(\.done).count) / Double(items.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(activity.name).font(.headline)
                Spacer()
                Text("\(items.filter(\.done).count)/\(items.count)")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(color).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 4)

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(get: { item.done }, set: { _ in toggle(index) })) {
                        Text(item.text)
                            .strikethrough(item.done)
                            .foregroundStyle(item.done ? Color.secondary : Color.primary)
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                    Button { remove(index) } label: { Image(systemName: "xmark").font(.caption) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove this item from the day")
                }
            }

            TextField("Add an item", text: $draft.newItem)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit(addItem)

            TextField("Note for the day", text: $draft.note)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .onSubmit(saveNote)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .onAppear { draft.note = stored?.note ?? "" }
    }

    private func save(_ newItems: [ChecklistItem], note: String? = nil) {
        journal.save(JournalEntry(date: date, activity: activity.id, items: newItems,
                                  note: note ?? stored?.note ?? ""))
    }

    private func toggle(_ index: Int) {
        var next = items
        next[index].done.toggle()
        save(next)
    }

    private func remove(_ index: Int) {
        var next = items
        next.remove(at: index)
        save(next)
    }

    private func addItem() {
        let text = draft.newItem.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        save(items + [ChecklistItem(text: text, done: false)])
        draft.newItem = ""
    }

    private func saveNote() {
        save(items, note: draft.note.trimmingCharacters(in: .whitespaces))
    }
}
