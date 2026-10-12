// Behaviour checks for the data layer: old history still loads, activities and the journal
// round-trip through their files, and the ledger maths are right. Run by tools/selftest.sh.
import Foundation

// The stores are main-actor isolated, so the checks run on the main actor (see the call at the bottom).
@MainActor var failures = 0
@MainActor func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("FAIL: \(message)")
    }
}

@MainActor func runChecks(dir: URL) {
let cal = Calendar.current
let today = cal.startOfDay(for: Date())
func daysAgo(_ n: Int, hour: Int = 12) -> Date {
    cal.date(bySettingHour: hour, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -n, to: today)!)!
}

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

// 1. A session line written before activities existed still decodes, and counts as Study.
let legacyFocus = #"{"completed":true,"end":"2026-10-04T21:33:20Z","minutes":50,"phase":"focus","start":"2026-10-04T20:43:20Z","topic":"Options pricing"}"#
let legacyRest = #"{"completed":true,"end":"2026-10-04T21:43:20Z","minutes":10,"phase":"rest","start":"2026-10-04T21:33:20Z","topic":""}"#
let oldFocus = try! decoder.decode(Session.self, from: Data(legacyFocus.utf8))
let oldRest = try! decoder.decode(Session.self, from: Data(legacyRest.utf8))
check(oldFocus.activityID == "study", "legacy focus session maps to study")
check(oldRest.activityID == "rest", "legacy rest session maps to rest")
check(oldFocus.minutes == 50, "legacy minutes are read unchanged")

// 2. Sessions with a custom activity keep it, and their phase still drives the goal and the streak.
func session(_ daysBack: Int, _ minutes: Double, _ activity: String?, phase: Phase = .focus) -> Session {
    let end = daysAgo(daysBack)
    return Session(start: end.addingTimeInterval(-minutes * 60), end: end, minutes: minutes,
                   phase: phase, topic: "", completed: true, activity: activity)
}
let sessions = [
    session(0, 30, "quiz"),
    session(1, 30, "quiz"),
    session(1, 20, "study"),
    session(2, 40, "quiz"),
    session(3, 15, nil, phase: .rest),
]
let ledger = Ledger(sessions)
check(ledger.minutes("quiz", on: daysAgo(1)) == 30, "per-day minutes for an activity")
check(ledger.minutes("quiz", since: daysAgo(1)) == 60, "minutes since a date counts only days in range")
check(ledger.minutes("quiz", since: nil) == 100, "all-time minutes for an activity")
check(ledger.activityTotals(since: nil).first?.id == "quiz", "largest activity comes first")
check(ledger.day(daysAgo(1)).focus == 50, "phase totals still combine quiz and study as focus")
check(ledger.day(daysAgo(3)).rest == 15, "rest session counts toward rest totals")

// 3. Streaks: quiz on today, yesterday and the day before is three in a row at a one-minute goal.
let streak = ledger.streak(goal: 1, today: daysAgo(0), activity: "quiz")
check(streak.current == 3, "quiz streak counts consecutive days logged (got \(streak.current))")
check(streak.longest == 3, "longest quiz streak")
check(ledger.streak(goal: 60, today: daysAgo(0)).current == 0, "focus goal streak is zero when no day reaches 60 minutes today")

// 4. Activities: defaults, resolve fallbacks, unique ids, labels and a save/reload round-trip.
let activitiesURL = dir.appendingPathComponent("activities.json")
let activityStore = ActivityStore(url: activitiesURL)
check(activityStore.activities.map(\.id) == ["study", "rest"], "defaults are study and rest")
check(activityStore.resolve("missing", kind: .rest) == "rest", "unknown rest id falls back to a rest activity")
check(activityStore.resolve("study", kind: .rest) == "rest", "wrong-kind id falls back to the right kind")
let quiz = activityStore.add(name: "Quiz", kind: .focus)
let quiz2 = activityStore.add(name: "Quiz", kind: .focus)
check(quiz.id == "quiz" && quiz2.id == "quiz-2", "duplicate names get unique ids")
check(activityStore.label("quiz") == "Quiz (quiz)", "duplicate names are disambiguated in labels")
check(activityStore.label("study") == "Study", "unique names are left alone")
let reloaded = ActivityStore(url: activitiesURL)
check(reloaded.activities.count == 4, "activities survive a reload (got \(reloaded.activities.count))")
activityStore.remove("quiz-2")
check(ActivityStore(url: activitiesURL).activities.count == 3, "removing an activity writes the file")
check(activityStore.name("quiz-2") == "quiz-2", "removed activity still shows by id in history")

// 5. Journal: the last line for a day and activity wins, and progress is done over total.
let journalURL = dir.appendingPathComponent("journal.jsonl")
let journal = JournalStore(url: journalURL)
let day = DayKey.string(today)
journal.save(JournalEntry(date: day, activity: "quiz", items: [ChecklistItem(text: "MCQ", done: false), ChecklistItem(text: "Review", done: false)], note: ""))
journal.save(JournalEntry(date: day, activity: "quiz", items: [ChecklistItem(text: "MCQ", done: true), ChecklistItem(text: "Review", done: false)], note: "good"))
let journalReloaded = JournalStore(url: journalURL)
let saved = journalReloaded.entry(day, "quiz")
check(saved?.note == "good", "later journal line replaces the earlier one")
check(saved?.fraction == 0.5, "journal progress is done over total")
check(journalReloaded.entry(day, "study") == nil, "other activities have no entry")

// 6. CSV: the old columns keep their order, and activity is appended last.
let sessionStore = SessionStore(url: nil)
sessionStore.load(sessions)
let header = sessionStore.csv().split(separator: "\n").first.map(String.init) ?? ""
check(header == "start,end,phase,minutes,topic,completed,activity", "CSV header keeps old columns and adds activity last")

if failures == 0 {
    print("selftest: all checks passed")
} else {
    print("selftest: \(failures) check(s) failed")
    exit(1)
}
}

MainActor.assumeIsolated {
    runChecks(dir: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
}
