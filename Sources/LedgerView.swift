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
}

struct LedgerView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings
    @StateObject private var ui = LedgerUI()
    var height: CGFloat = 820
    private var range: LedgerRange { ui.range }

    private var ledger: Ledger { store.ledger }
    private var cal: Calendar { ledger.calendar }
    private var goal: Double { Double(settings.dailyGoalMinutes) }
    private var todayStart: Date { cal.startOfDay(for: Date()) }

    private var since: Date? {
        if let n = range.days { return cal.date(byAdding: .day, value: -(n - 1), to: todayStart) }
        return ledger.firstDay
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
            Text("Finish a focus block and it lands here, along with your rest time, streaks and a year heatmap.")
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
        let kind: String
        let hours: Double
        var id: String { "\(date.timeIntervalSince1970)-\(kind)" }
    }

    private var buckets: [Bucket] {
        let start = since ?? todayStart
        var out: [Bucket] = []
        for (day, t) in ledger.byDay where day >= start {
            if t.focus > 0 { out.append(Bucket(date: day, kind: "Focus", hours: t.focus / 60)) }
            if t.rest > 0 { out.append(Bucket(date: day, kind: "Rest", hours: t.rest / 60)) }
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
        return VStack(alignment: .leading, spacing: 10) {
            Text("Time studied").font(.headline)
            Chart {
                ForEach(buckets) { b in
                    BarMark(x: .value("Day", b.date, unit: unit), y: .value("Hours", b.hours))
                        .foregroundStyle(by: .value("Kind", b.kind))
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
            .chartForegroundStyleScale(["Focus": Theme.focus, "Rest": Theme.rest])
            .chartXScale(domain: start...max(end, start.addingTimeInterval(86400)))
            .chartYAxisLabel("hours")
            .chartLegend(position: .top, alignment: .trailing)
            .frame(height: 160)
        }
    }

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Consistency").font(.headline)
            Heatmap(ledger: ledger, goal: goal)
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
                        Circle().fill(s.phase == .focus ? Theme.focus : Theme.rest).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.phase == .rest ? "Break" : (s.topic.isEmpty ? "Focus" : s.topic)).lineLimit(1)
                            Text(dateFmt.string(from: s.start) + (s.completed ? "" : " · stopped early"))
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

/// A year of days, one column per week, shaded by focus time against the daily goal.
struct Heatmap: View {
    let ledger: Ledger
    let goal: Double
    private static let monthFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()
    private let weeks = 53
    private let cell: CGFloat = 11
    private let gap: CGFloat = 2.5

    var body: some View {
        let cal = ledger.calendar
        let today = cal.startOfDay(for: Date())
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)!.start
        let gridStart = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)!

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: gap) {
                ForEach(0..<weeks, id: \.self) { w in
                    let first = cal.date(byAdding: .weekOfYear, value: w, to: gridStart)!
                    let prev = cal.date(byAdding: .weekOfYear, value: w - 1, to: gridStart)!
                    let newMonth = w == 0 || cal.component(.month, from: first) != cal.component(.month, from: prev)
                    Color.clear.frame(width: cell, height: 12)
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
                                Color.clear.frame(width: cell, height: cell)
                            } else {
                                let t = ledger.day(date)
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(Theme.heat(minutes: t.focus, goal: goal))
                                    .frame(width: cell, height: cell)
                                    .help(tip(date, t))
                            }
                        }
                    }
                }
            }
        }
    }

    private func tip(_ date: Date, _ t: DayTotals) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM yyyy"
        if t.focus == 0 && t.rest == 0 { return "\(f.string(from: date)): nothing logged" }
        return "\(f.string(from: date)): \(Fmt.minutes(t.focus)) focus, \(Fmt.minutes(t.rest)) rest"
    }
}
