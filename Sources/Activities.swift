import Foundation
import SwiftUI

/// Where Tempo keeps its files. The sessions, activities and journal stores all live here.
enum TempoFiles {
    static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tempo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// Whether an activity counts as focus (toward the daily goal, and Do Not Disturb) or as rest.
enum ActivityKind: String, Codable, CaseIterable, Identifiable {
    case focus, rest
    var id: String { rawValue }
    var label: String { self == .focus ? "Focus" : "Rest" }
}

/// A kind of time you track: Study, Quiz, Rest, or anything else.
/// Sessions store the id, so renaming an activity never rewrites history.
struct Activity: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var kind: ActivityKind
    var color: String
    /// Default checklist for the journal, e.g. "Chapter 7 MCQs" for a Quiz activity.
    var checklist: [String]

    static let study = Activity(id: "study", name: "Study", kind: .focus, color: "blue", checklist: [])
    static let rest = Activity(id: "rest", name: "Rest", kind: .rest, color: "teal", checklist: [])
}

struct ActivityFile: Codable {
    var version: Int
    var activities: [Activity]
}

/// The list of activities, kept in activities.json. A missing or unreadable file falls back to Study and Rest.
@MainActor
final class ActivityStore: ObservableObject {
    #if SCREENSHOTS
    static let shared = ActivityStore(url: nil)
    #else
    static let shared = ActivityStore(url: TempoFiles.directory.appendingPathComponent("activities.json"))
    #endif

    @Published private(set) var activities: [Activity] = [.study, .rest]
    let url: URL?

    init(url: URL?) {
        self.url = url
        reload()
    }

    func reload() {
        guard let url, let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ActivityFile.self, from: data),
              !file.activities.isEmpty else { return }
        activities = file.activities
    }

    func activity(_ id: String) -> Activity? { activities.first { $0.id == id } }

    /// Display name. An activity that was removed still shows under its stored id, so history stays readable.
    func name(_ id: String) -> String { activity(id)?.name ?? id }

    func color(_ id: String) -> Color { Theme.activityColor(activity(id)?.color ?? "blue") }

    func activities(of kind: ActivityKind) -> [Activity] { activities.filter { $0.kind == kind } }

    /// The selected id if it still exists with the right kind, otherwise the first activity of that kind.
    func resolve(_ id: String, kind: ActivityKind) -> String {
        if let a = activity(id), a.kind == kind { return a.id }
        return activities(of: kind).first?.id ?? (kind == .focus ? Activity.study.id : Activity.rest.id)
    }

    /// A unique, URL-safe id derived from the name, e.g. "Quiz 2" -> "quiz-2".
    func makeID(for name: String) -> String {
        let slug = name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
        let base = slug.isEmpty ? "activity" : slug
        var id = base
        var n = 2
        while activity(id) != nil {
            id = "\(base)-\(n)"
            n += 1
        }
        return id
    }

    /// Name for charts and legends. Two activities with the same name get their id appended so they stay distinct.
    func label(_ id: String) -> String {
        let name = name(id)
        return activities.filter { $0.name == name }.count > 1 ? "\(name) (\(id))" : name
    }

    /// Adds an activity with the first colour nobody uses yet.
    @discardableResult
    func add(name: String = "New activity", kind: ActivityKind = .focus) -> Activity {
        let used = Set(activities.map(\.color))
        let color = Theme.activityColors.map(\.name).first { !used.contains($0) } ?? "blue"
        let activity = Activity(id: makeID(for: name), name: name, kind: kind, color: color, checklist: [])
        save(activities + [activity])
        return activity
    }

    func update(_ id: String, _ mutate: (inout Activity) -> Void) {
        var list = activities
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        mutate(&list[index])
        save(list)
    }

    /// Removes the activity from the list only. Sessions and journal lines keep its id, so history is untouched.
    func remove(_ id: String) {
        save(activities.filter { $0.id != id })
    }

    /// Writes the whole list atomically. The file is small. History lives in sessions.jsonl and is never rewritten.
    func save(_ list: [Activity]) {
        activities = list
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(ActivityFile(version: 1, activities: list)) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
