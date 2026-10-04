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

    var id: String { "\(start.timeIntervalSince1970)-\(phase.rawValue)" }
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

/// Everything derived from the session log: per-day totals, streaks, topic breakdown.
struct Ledger {
    let calendar: Calendar
    let sessions: [Session]
    let byDay: [Date: DayTotals]

    init(_ sessions: [Session], calendar: Calendar = .current) {
        self.calendar = calendar
        self.sessions = sessions
        var days: [Date: DayTotals] = [:]
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
        }
        byDay = days
    }

    var firstDay: Date? { byDay.keys.min() }

    func day(_ date: Date) -> DayTotals { byDay[calendar.startOfDay(for: date)] ?? DayTotals() }

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

    /// Consecutive days with at least `goal` minutes of focus. Today does not break the
    /// streak until it has ended, so the current run counts back from yesterday if today is short.
    func streak(goal: Double, today: Date = Date()) -> (current: Int, longest: Int) {
        let goal = max(goal, 1)
        let todayStart = calendar.startOfDay(for: today)
        func hit(_ d: Date) -> Bool { (byDay[d]?.focus ?? 0) >= goal }
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

    static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tempo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.jsonl")
    }

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

    func csv() -> String {
        let iso = ISO8601DateFormatter()
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows = ["start,end,phase,minutes,topic,completed"]
        for s in sessions {
            rows.append([iso.string(from: s.start), iso.string(from: s.end), s.phase.rawValue,
                         String(format: "%.2f", s.minutes), esc(s.topic), s.completed ? "true" : "false"].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }
}
