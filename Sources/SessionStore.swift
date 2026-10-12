import Foundation

enum Phase: String, Codable {
    case focus, rest
}

struct Session: Codable, Identifiable {
    let start: Date
    let end: Date
    let minutes: Double
    let phase: Phase
    let topic: String
    let completed: Bool
    /// Activity id, such as "study" or "quiz". Sessions written before activities existed have none,
    /// and count as Study or Rest by phase.
    let activity: String?

    init(start: Date, end: Date, minutes: Double, phase: Phase, topic: String, completed: Bool, activity: String? = nil) {
        self.start = start
        self.end = end
        self.minutes = minutes
        self.phase = phase
        self.topic = topic
        self.completed = completed
        self.activity = activity
    }

    var activityID: String { activity ?? (phase == .rest ? Activity.rest.id : Activity.study.id) }
    var id: String { "\(start.timeIntervalSince1970)-\(activityID)" }
}

struct DayTotals {
    var focus = 0.0      // minutes
    var rest = 0.0       // minutes
    var sessions = 0     // completed focus sessions
}

enum Fmt {
    static func minutes(_ m: Double) -> String {
        let total = Int(m.rounded())
        let h = total / 60, r = total % 60
        if h > 0 { return r == 0 ? "\(h)h" : "\(h)h \(r)m" }
        return "\(r)m"
    }
}

/// Everything derived from the session log: per-day totals, per-activity minutes, streaks, topic breakdown.
struct Ledger {
    let calendar: Calendar
    let sessions: [Session]
    /// Focus and rest minutes per day, by phase. These drive the daily goal and the streak.
    let byDay: [Date: DayTotals]
    /// Minutes per activity id, per day. Drives the stacked chart and the habit views.
    let byDayActivity: [Date: [String: Double]]

    init(_ sessions: [Session], calendar: Calendar = .current) {
        self.calendar = calendar
        self.sessions = sessions
        var days: [Date: DayTotals] = [:]
        var perActivity: [Date: [String: Double]] = [:]
        for s in sessions {
            let key = calendar.startOfDay(for: s.end)
            var t = days[key, default: DayTotals()]
            switch s.phase {
            case .focus:
                t.focus += s.minutes
                if s.completed { t.sessions += 1 }
            case .rest:
                t.rest += s.minutes
            }
            days[key] = t
            perActivity[key, default: [:]][s.activityID, default: 0] += s.minutes
        }
        byDay = days
        byDayActivity = perActivity
    }

    var firstDay: Date? { byDay.keys.min() }

    func day(_ date: Date) -> DayTotals { byDay[calendar.startOfDay(for: date)] ?? DayTotals() }

    /// Minutes logged for one activity on one day.
    func minutes(_ activity: String, on date: Date) -> Double {
        byDayActivity[calendar.startOfDay(for: date)]?[activity] ?? 0
    }

    func total(since: Date?) -> DayTotals {
        let from = since.map { calendar.startOfDay(for: $0) }
        var out = DayTotals()
        for (day, t) in byDay where from == nil || day >= from! {
            out.focus += t.focus
            out.rest += t.rest
            out.sessions += t.sessions
        }
        return out
    }

    func activeDays(since: Date?) -> Int {
        let from = since.map { calendar.startOfDay(for: $0) }
        return byDay.filter { ($0.value.focus > 0) && (from == nil || $0.key >= from!) }.count
    }

    /// Minutes per activity since a date, largest first.
    func activityTotals(since: Date?) -> [(id: String, minutes: Double)] {
        let from = since.map { calendar.startOfDay(for: $0) }
        var sums: [String: Double] = [:]
        for (day, perActivity) in byDayActivity where from == nil || day >= from! {
            for (id, m) in perActivity { sums[id, default: 0] += m }
        }
        return sums.map { (id: $0.key, minutes: $0.value) }.sorted { $0.minutes > $1.minutes }
    }

    /// Minutes logged for one activity since a date (nil means all time).
    func minutes(_ activity: String, since: Date?) -> Double {
        let from = since.map { calendar.startOfDay(for: $0) }
        return byDayActivity.reduce(0) { sum, entry in
            guard from == nil || entry.key >= from! else { return sum }
            return sum + (entry.value[activity] ?? 0)
        }
    }

    /// Days with any minutes for one activity since a date.
    func activeDays(_ activity: String, since: Date?) -> Int {
        let from = since.map { calendar.startOfDay(for: $0) }
        return byDayActivity.filter { ($0.value[activity] ?? 0) > 0 && (from == nil || $0.key >= from!) }.count
    }

    /// Consecutive days meeting `goal` minutes. With `activity` set, it counts that activity's minutes instead
    /// of focus. Today does not break the streak until it has ended, so the run counts back from yesterday if today is short.
    func streak(goal: Double, today: Date = Date(), activity: String? = nil) -> (current: Int, longest: Int) {
        let goal = max(goal, 1)
        let todayStart = calendar.startOfDay(for: today)
        func minutesOn(_ d: Date) -> Double {
            guard let activity else { return byDay[d]?.focus ?? 0 }
            return byDayActivity[d]?[activity] ?? 0
        }
        func hit(_ d: Date) -> Bool { minutesOn(d) >= goal }
        func shift(_ d: Date, _ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: d)! }

        var cursor = hit(todayStart) ? todayStart : shift(todayStart, -1)
        var current = 0
        while hit(cursor) {
            current += 1
            cursor = shift(cursor, -1)
        }

        guard let first = firstDay else { return (0, 0) }
        var longest = 0, run = 0
        var d = first
        while d <= todayStart {
            if hit(d) { run += 1; longest = max(longest, run) } else { run = 0 }
            d = shift(d, 1)
        }
        return (current, longest)
    }

    func topics(since: Date?) -> [(topic: String, minutes: Double)] {
        let from = since.map { calendar.startOfDay(for: $0) }
        var sums: [String: Double] = [:]
        for s in sessions where s.phase == .focus && (from == nil || s.end >= from!) {
            let key = s.topic.trimmingCharacters(in: .whitespaces)
            sums[key.isEmpty ? "No topic" : key, default: 0] += s.minutes
        }
        return sums.map { (topic: $0.key, minutes: $0.value) }.sorted { $0.minutes > $1.minutes }
    }
}

@MainActor
final class SessionStore: ObservableObject {
    #if SCREENSHOTS
    static let shared = SessionStore(url: nil)
    #else
    static let shared = SessionStore(url: SessionStore.defaultURL)
    #endif

    @Published private(set) var sessions: [Session] = []
    @Published private(set) var ledger = Ledger([])
    let url: URL?

    static var defaultURL: URL { TempoFiles.directory.appendingPathComponent("sessions.jsonl") }

    init(url: URL?) {
        self.url = url
        reload()
    }

    func reload() {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        load(text.split(separator: "\n").compactMap { try? decoder.decode(Session.self, from: Data($0.utf8)) })
    }

    /// Replaces the in-memory history (used by reload and by the screenshot tool).
    func load(_ list: [Session]) {
        sessions = list.sorted { $0.start < $1.start }
        ledger = Ledger(sessions)
    }

    func append(_ session: Session) {
        load(sessions + [session])
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard var line = try? encoder.encode(session) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }

    /// Columns are only ever added at the end, so spreadsheets built on the old export keep working.
    func csv() -> String {
        let iso = ISO8601DateFormatter()
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows = ["start,end,phase,minutes,topic,completed,activity"]
        for s in sessions {
            rows.append([iso.string(from: s.start), iso.string(from: s.end), s.phase.rawValue,
                         String(format: "%.2f", s.minutes), esc(s.topic), s.completed ? "true" : "false",
                         esc(s.activityID)].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }
}
