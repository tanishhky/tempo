import Foundation

struct ChecklistItem: Codable, Equatable {
    var text: String
    var done: Bool
}

/// One day's checklist for one activity, stored as a line in journal.jsonl.
/// Lines are append-only: the last line for a (date, activity) pair is the current one.
struct JournalEntry: Codable, Equatable {
    /// Local calendar day, yyyy-MM-dd.
    let date: String
    let activity: String
    var items: [ChecklistItem]
    var note: String

    var doneCount: Int { items.filter(\.done).count }
    var fraction: Double { items.isEmpty ? 0 : Double(doneCount) / Double(items.count) }
}

enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ key: String) -> Date? { formatter.date(from: key) }
}

@MainActor
final class JournalStore: ObservableObject {
    #if SCREENSHOTS
    static let shared = JournalStore(url: nil)
    #else
    static let shared = JournalStore(url: TempoFiles.directory.appendingPathComponent("journal.jsonl"))
    #endif

    /// Current entry per "date|activity" key.
    @Published private(set) var entries: [String: JournalEntry] = [:]
    let url: URL?

    init(url: URL?) {
        self.url = url
        reload()
    }

    static func key(_ date: String, _ activity: String) -> String { "\(date)|\(activity)" }

    func entry(_ date: String, _ activity: String) -> JournalEntry? {
        entries[Self.key(date, activity)]
    }

    func reload() {
        // Without a file (the screenshot tool) the in-memory entries are the journal, so leave them alone.
        guard let url else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            entries = [:]
            return
        }
        let decoder = JSONDecoder()
        var map: [String: JournalEntry] = [:]
        for line in text.split(separator: "\n") {
            guard let entry = try? decoder.decode(JournalEntry.self, from: Data(line.utf8)) else { continue }
            map[Self.key(entry.date, entry.activity)] = entry
        }
        entries = map
    }

    func save(_ entry: JournalEntry) {
        entries[Self.key(entry.date, entry.activity)] = entry
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }
}
