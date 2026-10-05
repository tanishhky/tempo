import SwiftUI

/// Local view state as an object: the @State macro needs the full Xcode toolchain, Tempo builds with the Command Line Tools alone.
final class SettingsUI: ObservableObject {
    @Published var shortcutsStatus = "Checking..."
    @Published var macResult = ""
    @Published var phoneResult = ""
    @Published var phoneOK: Bool?
    @Published var busy = false
}

struct SettingsView: View {
    @ObservedObject var m: TimerModel
    @ObservedObject var settings: AppSettings
    let bridge: FocusBridge
    @StateObject private var ui = SettingsUI()
    var height: CGFloat = 760

    var body: some View {
        Form {
            Section("Daily goal") {
                Stepper(value: $settings.dailyGoalMinutes, in: 15...600, step: 15) {
                    HStack {
                        Text("Focus goal")
                        Spacer()
                        Text(Fmt.minutes(Double(settings.dailyGoalMinutes))).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Text("A day counts toward your streak when you focus for at least this long.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Do Not Disturb on this Mac") {
                Toggle("Turn on Focus while a session runs", isOn: $settings.dndMac)
                Text("macOS has no direct switch for Do Not Disturb, so Tempo runs two Shortcuts you create once:")
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    step("1", "Open Shortcuts and make a shortcut named **\(AppSettings.macOnShortcut)**.")
                    step("2", "Add the action **Set Focus**: Do Not Disturb, Turn On, Until Turned Off.")
                    step("3", "Make a second one named **\(AppSettings.macOffShortcut)** with Set Focus set to Turn Off.")
                }
                HStack {
                    Button("Open Shortcuts") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
                    Button("Recheck") { Task { ui.shortcutsStatus = await bridge.macShortcutsStatus() } }
                    Spacer()
                    Text(ui.shortcutsStatus).font(.caption).foregroundStyle(ui.shortcutsStatus.hasPrefix("Both") ? .green : .orange)
                }
                HStack {
                    Button("Test on") { run { ui.macResult = await bridge.testMac(on: true) } }
                    Button("Test off") { run { ui.macResult = await bridge.testMac(on: false) } }
                    Text(ui.macResult).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .disabled(ui.busy)
            }

            Section("Do Not Disturb on your Android phone") {
                Toggle("Also silence the phone while a session runs", isOn: $settings.dndPhone)
                Text("Needs the Tempo Companion app (in the android folder of the repo) running on a phone on the same Wi-Fi. It shows the address and token to enter here.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Phone address", text: $settings.phoneHost, prompt: Text("192.168.1.42"))
                TextField("Port", value: $settings.phonePort, format: .number.grouping(.never))
                TextField("Token", text: $settings.phoneToken, prompt: Text("Paste the token from the phone"))
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                HStack {
                    Button("Test connection") {
                        run {
                            let r = await bridge.testPhone()
                            ui.phoneOK = r.ok && r.dndAccess != false
                            ui.phoneResult = r.ok ? (r.dndAccess == false ? "Connected, but DND access is not granted on the phone." : "Connected. DND access granted.") : r.message
                        }
                    }
                    .disabled(ui.busy)
                    Text(ui.phoneResult).font(.caption).lineLimit(2)
                        .foregroundStyle(ui.phoneOK == true ? .green : .orange)
                }
                Text("Tempo only talks to this one address, over your local network, while the toggle is on. macOS asks once to allow local network access.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("During breaks") {
                Toggle("Keep Do Not Disturb on during breaks", isOn: $settings.dndDuringBreaks)
            }

            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { m.launchAtLogin }, set: { m.setLaunchAtLogin($0) }))
                Button("Show session log in Finder") {
                    if let url = m.store.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: height)
        .task {
            #if SCREENSHOTS
            ui.shortcutsStatus = "Both shortcuts found."
            #else
            ui.shortcutsStatus = await bridge.macShortcutsStatus()
            #endif
        }
    }

    private func step(_ n: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(n).font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 12)
            Text(text).font(.caption)
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        ui.busy = true
        Task {
            await work()
            ui.busy = false
        }
    }
}
