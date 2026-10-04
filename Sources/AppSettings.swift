import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    nonisolated static let macOnShortcut = "Tempo Focus On"
    nonisolated static let macOffShortcut = "Tempo Focus Off"

    private let defaults = UserDefaults.standard

    @Published var dailyGoalMinutes: Int { didSet { defaults.set(dailyGoalMinutes, forKey: "dailyGoalMinutes") } }
    @Published var dndMac: Bool { didSet { defaults.set(dndMac, forKey: "dndMac") } }
    @Published var dndPhone: Bool { didSet { defaults.set(dndPhone, forKey: "dndPhone") } }
    @Published var dndDuringBreaks: Bool { didSet { defaults.set(dndDuringBreaks, forKey: "dndDuringBreaks") } }
    @Published var phoneHost: String { didSet { defaults.set(phoneHost, forKey: "phoneHost") } }
    @Published var phonePort: Int { didSet { defaults.set(phonePort, forKey: "phonePort") } }
    @Published var phoneToken: String { didSet { defaults.set(phoneToken, forKey: "phoneToken") } }

    init() {
        let goal = defaults.integer(forKey: "dailyGoalMinutes")
        dailyGoalMinutes = goal > 0 ? goal : 120
        dndMac = defaults.bool(forKey: "dndMac")
        dndPhone = defaults.bool(forKey: "dndPhone")
        dndDuringBreaks = defaults.bool(forKey: "dndDuringBreaks")
        phoneHost = defaults.string(forKey: "phoneHost") ?? ""
        let port = defaults.integer(forKey: "phonePort")
        phonePort = port > 0 ? port : 8765
        phoneToken = defaults.string(forKey: "phoneToken") ?? ""
    }
}
