import AppKit
import ServiceManagement
import UserNotifications

enum Phase: String, Codable {
    case focus, rest
}

struct Session: Codable {
    let start: Date
    let end: Date
    let minutes: Double
    let phase: Phase
    let topic: String
    let completed: Bool
}

@MainActor
final class TimerModel: ObservableObject {
    static let shared = TimerModel()

    @Published var phase: Phase = .focus {
        didSet { if phase != oldValue { secondsLeft = Int(total) } }
    }
    @Published var focusMinutes: Int {
        didSet { defaults.set(focusMinutes, forKey: "focusMinutes"); refreshIdle() }
    }
    @Published var restMinutes: Int {
        didSet { defaults.set(restMinutes, forKey: "restMinutes"); refreshIdle() }
    }
    @Published var topic: String {
        didSet { defaults.set(topic, forKey: "topic") }
    }
    @Published private(set) var secondsLeft = 0
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var todaySeconds: TimeInterval = 0
    @Published private(set) var todaySessions = 0
    @Published private(set) var weekSeconds: TimeInterval = 0
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let defaults = UserDefaults.standard
    private var sessionStart: Date?
    private var ticker: Timer?
    private var activity: NSObjectProtocol?
    private let endNotificationID = "tempo.end"

    private let logURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tempo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.jsonl")
    }()

    init() {
        let f = defaults.integer(forKey: "focusMinutes")
        let r = defaults.integer(forKey: "restMinutes")
        focusMinutes = f > 0 ? f : 50
        restMinutes = r > 0 ? r : 10
        topic = defaults.string(forKey: "topic") ?? ""
        secondsLeft = Int(total)
        loadStats()
    }

    // MARK: State

    var total: TimeInterval { TimeInterval(minutes * 60) }
    var minutes: Int { phase == .focus ? focusMinutes : restMinutes }
    var isRunning: Bool { endDate != nil }
    var isPaused: Bool { pausedRemaining != nil }
    var isIdle: Bool { endDate == nil && pausedRemaining == nil }
    var progress: Double { total > 0 ? max(0, min(1, 1 - Double(secondsLeft) / total)) : 0 }

    private var remaining: TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSinceNow) }
        return pausedRemaining ?? total
    }

    var clock: String {
        let s = max(0, secondsLeft)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    var statusLine: String {
        if isPaused { return "Paused" }
        if phase == .rest { return isRunning ? "Stand up, breathe" : "Break" }
        return isRunning ? "Focusing" : "Ready"
    }

    // MARK: Actions

    func start() {
        guard !isRunning else { return }
        if isIdle { sessionStart = Date() }
        let length = pausedRemaining ?? total
        endDate = Date().addingTimeInterval(length)
        pausedRemaining = nil
        scheduleEndNotification(after: length)
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Study timer running")
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func pause() {
        guard isRunning else { return }
        pausedRemaining = remaining
        endDate = nil
        stopRunning()
        updateSeconds()
    }

    func toggle() { isRunning ? pause() : start() }

    func reset() {
        logPartialFocus()
        clearRun()
    }

    func skip() {
        logPartialFocus()
        clearRun()
        phase = phase == .focus ? .rest : .focus
    }

    func setMinutes(_ value: Int) {
        guard isIdle else { return }
        if phase == .focus { focusMinutes = value } else { restMinutes = value }
    }

    func nudge(_ delta: Int) {
        let range = phase == .focus ? 5...240 : 5...60
        setMinutes(min(range.upperBound, max(range.lowerBound, minutes + delta)))
    }

    func handle(_ url: URL) {
        guard url.scheme == "tempo" else { return }
        switch url.host ?? "" {
        case "start": start()
        case "pause": pause()
        case "toggle": toggle()
        case "reset": reset()
        case "skip": skip()
        default: break
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Tempo: launch at login change failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Internals

    private func tick() {
        if isRunning && remaining <= 0 { complete() } else { updateSeconds() }
    }

    private func updateSeconds() {
        let s = Int(remaining.rounded(.up))
        if s != secondsLeft { secondsLeft = s }
    }

    private func refreshIdle() {
        if isIdle { secondsLeft = Int(total) }
    }

    private func complete() {
        let finished = phase
        if let start = sessionStart {
            append(Session(start: start, end: Date(), minutes: total / 60, phase: finished,
                           topic: finished == .focus ? topic : "", completed: true))
        }
        endDate = nil
        clearRun(cancelNotification: false)
        NSSound(named: "Glass")?.play()
        phase = finished == .focus ? .rest : .focus
    }

    private func clearRun(cancelNotification: Bool = true) {
        endDate = nil
        pausedRemaining = nil
        sessionStart = nil
        stopRunning(cancelNotification: cancelNotification)
        secondsLeft = Int(total)
    }

    private func stopRunning(cancelNotification: Bool = true) {
        ticker?.invalidate()
        ticker = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        if cancelNotification {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [endNotificationID])
        }
    }

    private func logPartialFocus() {
        guard phase == .focus, let start = sessionStart else { return }
        let elapsed = total - remaining
        guard elapsed >= 60 else { return }
        append(Session(start: start, end: Date(), minutes: elapsed / 60, phase: .focus,
                       topic: topic, completed: false))
    }

    private func scheduleEndNotification(after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        if phase == .focus {
            content.title = "Focus done"
            content.body = "\(focusMinutes) min" + (topic.isEmpty ? "" : " of \(topic)") + ". Take \(restMinutes)."
        } else {
            content.title = "Break over"
            content.body = "Back to it: \(focusMinutes) min of focus."
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: endNotificationID, content: content, trigger: trigger))
    }

    // MARK: Log + stats

    private func append(_ session: Session) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard var line = try? encoder.encode(session) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: logURL)
        }
        loadStats()
    }

    func loadStats() {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekStart = cal.date(byAdding: .day, value: -6, to: today) ?? today
        var day: TimeInterval = 0, week: TimeInterval = 0, done = 0
        for line in text.split(separator: "\n") {
            guard let s = try? decoder.decode(Session.self, from: Data(line.utf8)), s.phase == .focus else { continue }
            if s.end >= today {
                day += s.minutes * 60
                if s.completed { done += 1 }
            }
            if s.end >= weekStart { week += s.minutes * 60 }
        }
        todaySeconds = day
        todaySessions = done
        weekSeconds = week
    }

    // MARK: Menu bar label

    var labelImage: NSImage {
        let symbol: String
        if isIdle { symbol = "timer" }
        else if isPaused { symbol = "pause.circle" }
        else { symbol = phase == .focus ? "brain" : "cup.and.saucer" }
        return MenuBarLabel.render(symbol: symbol, text: isIdle ? nil : clock)
    }
}

enum MenuBarLabel {
    static func render(symbol: String, text: String?) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        let string = text.map { NSAttributedString(string: $0, attributes: attrs) }
        let iconSize = icon?.size ?? .zero
        let textSize = string?.size() ?? .zero
        let gap: CGFloat = string == nil ? 0 : 4
        let height: CGFloat = 18
        let width = ceil(iconSize.width + gap + textSize.width)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            icon?.draw(in: NSRect(x: 0, y: (height - iconSize.height) / 2, width: iconSize.width, height: iconSize.height))
            string?.draw(at: NSPoint(x: iconSize.width + gap, y: (height - textSize.height) / 2))
            return true
        }
        image.isTemplate = true
        return image
    }
}

#if SCREENSHOTS
// Fixed states for the README images; compiled only by tools/screenshots.sh.
extension TimerModel {
    func stage(phase: Phase, remaining: Int, running: Bool, paused: Bool = false, topic: String,
               today: TimeInterval, sessions: Int, week: TimeInterval) {
        self.phase = phase
        self.topic = topic
        endDate = running ? Date().addingTimeInterval(TimeInterval(remaining)) : nil
        pausedRemaining = paused ? TimeInterval(remaining) : nil
        secondsLeft = remaining
        todaySeconds = today
        todaySessions = sessions
        weekSeconds = week
    }
}
#endif
