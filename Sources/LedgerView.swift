import Charts
import SwiftUI
import UniformTypeIdentifiers

enum LedgerRange: String, CaseIterable, Identifiable {
    case week = "7 days", month = "30 days", quarter = "90 days", year = "1 year", all = "All time"
    var id: String { rawValue }
    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .year: 365
        case .all: nil
        }
    }
}

/// Local view state as an object: the @State macro needs the full Xcode toolchain, Tempo builds with the Command Line Tools alone.
final class LedgerUI: ObservableObject {
    @Published var range: LedgerRange = .month
    /// The activity the Habits section is showing.
    @Published var habitID = Activity.study.id
}

struct LedgerView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var activities: ActivityStore
    @StateObject private var ui = LedgerUI()
    var height: CGFloat = 900
    private var range: LedgerRange { ui.range }

    private var ledger: Ledger { store.ledger }
    private var cal: Calendar { ledger.calendar }
    private var goal: Double { Double(settings.dailyGoalMinutes) }
    private var todayStart: Date { cal.startOfDay(for: Date()) }

    private var since: Date? {
        if let n = range.days { return cal.date(byAdding: .day, value: -(n - 1), to: todayStart) }
        return ledger.firstDay
    }

    /// The habit on show. Falls back to the first activity if the chosen one was removed.
    private var habit: Activity? {
        activities.activity(ui.habitID) ?? activities.activities.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if ledger.sessions.isEmpty {
                    empty
                } else {
                    tiles
                    chartSection
                    if let habit { habitSection(habit) }
                    heatmapSection
                    HStack(alignment: .top, spacing: 28) {
                        topicsSection
                        recentSection
                    }
                }
            }
            .padding(28)
        }
        .frame(width: 780, height: height)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { store.reload() }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Text("Ledger").font(.system(size: 26, weight: .semibold, design: .rounded))
            Spacer()
            Picker("", selection: $ui.range) {
                ForEach(LedgerRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 330)
            Button { exportCSV() } label: { Image(systemName: "square.and.arrow.up") }
                .help("Export every session as CSV")
                .disabled(ledger.sessions.isEmpty)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("No sessions yet").font(.headline)
            Text("Finish a block and it lands here, under its activity, along with streaks and a year heatmap.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 80)
    }

    private var tiles: some View {
        let t = ledger.total(since: since)
        let active = ledger.activeDays(since: since)
        let streak = ledger.streak(goal: goal)
        return HStack(spacing: 12) {
            tile("Focus", Fmt.minutes(t.focus), active > 0 ? "avg \(Fmt.minutes(t.focus / Double(active))) per active day" : "no focus yet", Theme.focus)
            tile("Rest", Fmt.minutes(t.rest), t.focus > 0 ? "\(Int((t.rest / t.focus * 100).rounded()))% of focus time" : "no breaks yet", Theme.rest)
            tile("Sessions", "\(t.sessions)", "\(active) active day\(active == 1 ? "" : "s")", .primary)
            tile("Streak", "\(streak.current) day\(streak.current == 1 ? "" : "s")", "best \(streak.longest) · goal \(Fmt.minutes(goal))/day", Theme.flame)
        }
    }

    private func tile(_ title: String, _ value: String, _ note: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(color).monospacedDigit()
            Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }

    private struct Bucket: Identifiable {
        let date: Date
        let name: String
        let hours: Double
        var id: String { "\(date.timeIntervalSince1970)-\(name)" }
    }

    /// One stack segment per activity per day.
    private var buckets: [Bucket] {
        let start = since ?? todayStart
        var out: [Bucket] = []
        for (day, perActivity) in ledger.byDayActivity where day >= start {
            for (id, minutes) in perActivity where minutes > 0 {
                out.append(Bucket(date: day, name: activities.label(id), hours: minutes / 60))
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    private var unit: Calendar.Component {
        switch range {
        case .week, .month, .quarter: .day
        case .year: .weekOfYear
        case .all:
            (since.map { cal.dateComponents([.day], from: $0, to: todayStart).day ?? 0 } ?? 0) > 400 ? .month : .weekOfYear
        }
    }

    private var chartSection: some View {
        let start = since ?? todayStart
        let end = cal.date(byAdding: .day, value: 1, to: todayStart)!
        let order = ledger.activityTotals(since: since).map(\.id)
        let names = order.map(activities.label)
        let colors = order.map(activities.color)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Time by activity").font(.headline)
            Chart {
                ForEach(buckets) { b in
                    BarMark(x: .value("Day", b.date, unit: unit), y: .value("Hours", b.hours))
                        .foregroundStyle(by: .value("Activity", b.name))
                }
                if unit == .day {
                    RuleMark(y: .value("Goal", goal / 60))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.flame.opacity(0.8))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("goal").font(.caption2).foregroundStyle(Theme.flame)
                        }
                }
            }
            .chartForegroundStyleScale(domain: names, range: colors)
            .chartXScale(domain: start...max(end, start.addingTimeInterval(86400)))
            .chartYAxisLabel("hours")
            .chartLegend(position: .top, alignment: .trailing)
            .frame(height: 160)
        }
    }

    /// Trend for one activity: totals, a streak of days logged, a daily bar chart and a year heatmap.
    private func habitSection(_ habit: Activity) -> some View {
        let color = activities.color(habit.id)
        let t = ledger.minutes(habit.id, since: since)
        let days = ledger.activeDays(habit.id, since: since)
        let streak = ledger.streak(goal: 1, activity: habit.id)
        let start = since ?? todayStart
        let series = dailySeries(habit.id, from: start)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Habits").font(.headline)
                Spacer()
                Picker("", selection: $ui.habitID) {
                    ForEach(activities.activities) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            HStack(spacing: 12) {
                tile(habit.name, Fmt.minutes(t), days > 0 ? "avg \(Fmt.minutes(t / Double(days))) per day you logged it" : "not logged in this range", color)
                tile("Days logged", "\(days)", "in this range", color)
                tile("Logged in a row", "\(streak.current)", "best \(streak.longest) day\(streak.longest == 1 ? "" : "s")", color)
            }
            Chart(series) { p in
                BarMark(x: .value("Day", p.date, unit: unit), y: .value("Minutes", p.minutes))
                    .foregroundStyle(color)
            }
            .chartXScale(domain: start...max(todayStart.addingTimeInterval(86400), start.addingTimeInterval(86400)))
            .chartYAxisLabel("minutes")
            .frame(height: 110)
            HeatLegend(color: color)
            habitHeatmap(habit.id, color: color)
        }
    }

    private struct DayPoint: Identifiable {
        let date: Date
        let minutes: Double
        var id: Date { date }
    }

    /// Minutes for one activity per day from `start` to today, zero-filled, for the bar chart.
    private func dailySeries(_ activity: String, from start: Date) -> [DayPoint] {
        var out: [DayPoint] = []
        var d = start
        while d <= todayStart {
            let m = ledger.minutes(activity, on: d)
            if m > 0 { out.append(DayPoint(date: d, minutes: m)) }
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }

    private func habitHeatmap(_ activity: String, color: Color) -> some View {
        let peak = max(ledger.byDayActivity.values.compactMap { $0[activity] }.max() ?? 1, 1)
        return Heatmap(calendar: cal) { date in
            let m = ledger.minutes(activity, on: date)
            let fill = m > 0 ? color.opacity(0.25 + 0.75 * min(1, m / peak)) : Color.primary.opacity(0.07)
            return HeatCell(fill: fill, tip: "\(Self.dayFmt.string(from: date)): \(m > 0 ? Fmt.minutes(m) : "nothing logged")")
        }
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM yyyy"
        return f
    }()

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Consistency").font(.headline)
            Heatmap(calendar: cal) { date in
                let t = ledger.day(date)
                let fill = Theme.heat(minutes: t.focus, goal: goal)
                let tip = t.focus == 0 && t.rest == 0
                    ? "\(Self.dayFmt.string(from: date)): nothing logged"
                    : "\(Self.dayFmt.string(from: date)): \(Fmt.minutes(t.focus)) focus, \(Fmt.minutes(t.rest)) rest"
                return HeatCell(fill: fill, tip: tip)
            }
            HStack(spacing: 4) {
                Spacer()
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach([0.0, 0.2, 0.4, 0.7, 1.0], id: \.self) { f in
                    RoundedRectangle(cornerRadius: 2).fill(Theme.heat(minutes: f * goal, goal: goal)).frame(width: 11, height: 11)
                }
                Text("Goal met").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var topicsSection: some View {
        let topics = Array(ledger.topics(since: since).prefix(6))
        let top = max(topics.first?.minutes ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("By topic").font(.headline)
            if topics.isEmpty {
                Text("Nothing in this range.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(topics, id: \.topic) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(item.topic).lineLimit(1)
                        Spacer()
                        Text(Fmt.minutes(item.minutes)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.callout)
                    GeometryReader { geo in
                        Capsule().fill(Theme.focus.opacity(0.75)).frame(width: geo.size.width * item.minutes / top)
                    }
                    .frame(height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var recentSection: some View {
        let recent = Array(ledger.sessions.suffix(40).reversed())
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "EEE d MMM, HH:mm"
        return VStack(alignment: .leading, spacing: 8) {
            Text("Recent sessions").font(.headline)
            VStack(spacing: 0) {
                ForEach(recent.prefix(8)) { s in
                    HStack(spacing: 8) {
                        Circle().fill(activities.color(s.activityID)).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.topic.isEmpty ? activities.name(s.activityID) : s.topic).lineLimit(1)
                            Text(activities.name(s.activityID) + " · " + dateFmt.string(from: s.start) + (s.completed ? "" : " · stopped early"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Fmt.minutes(s.minutes)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.callout)
                    .padding(.vertical, 5)
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tempo-sessions.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.csv().write(to: url, atomically: true, encoding: .utf8)
    }
}

/// One day's cell in a heatmap: its fill and the tooltip shown on hover.
struct HeatCell {
    let fill: Color
    let tip: String
}

/// A year of days, one column per week. `cell` decides each day's colour and tooltip.
struct Heatmap: View {
    let calendar: Calendar
    let cell: (Date) -> HeatCell
    private static let monthFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()
    private let weeks = 53
    private let size: CGFloat = 11
    private let gap: CGFloat = 2.5

    var body: some View {
        let cal = calendar
        let today = cal.startOfDay(for: Date())
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)!.start
        let gridStart = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)!

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: gap) {
                ForEach(0..<weeks, id: \.self) { w in
                    let first = cal.date(byAdding: .weekOfYear, value: w, to: gridStart)!
                    let prev = cal.date(byAdding: .weekOfYear, value: w - 1, to: gridStart)!
                    let newMonth = w == 0 || cal.component(.month, from: first) != cal.component(.month, from: prev)
                    Color.clear.frame(width: size, height: 12)
                        .overlay(alignment: .leading) {
                            if newMonth { Text(Self.monthFmt.string(from: first)).font(.system(size: 9)).foregroundStyle(.secondary).fixedSize() }
                        }
                }
            }
            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { d in
                            let date = cal.date(byAdding: .day, value: w * 7 + d, to: gridStart)!
                            if date > today {
                                Color.clear.frame(width: size, height: size)
                            } else {
                                let c = cell(date)
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(c.fill)
                                    .frame(width: size, height: size)
                                    .help(c.tip)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Less-to-more swatches in one colour, for the habit and journal heatmaps.
struct HeatLegend: View {
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Spacer()
            Text("Less").font(.caption2).foregroundStyle(.secondary)
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { f in
                RoundedRectangle(cornerRadius: 2)
                    .fill(f == 0 ? Color.primary.opacity(0.07) : color.opacity(0.25 + 0.75 * f))
                    .frame(width: 11, height: 11)
            }
            Text("More").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
