import SwiftUI

/// Local view state as an object: the @State macro needs the full Xcode toolchain, Tempo builds with the Command Line Tools alone.
final class SettingsUI: ObservableObject {
    @Published var shortcutsStatus = "Checking..."
    @Published var macResult = ""
    @Published var phoneResult = ""
    @Published var phoneOK: Bool?
    @Published var busy = false
}

/// One activity in Settings: its name, kind, colour, and the checklist the journal shows for it.
private struct ActivityRow: View {
    @ObservedObject var activities: ActivityStore
    let activity: Activity
    @StateObject private var draft = CardDraft()

    private var sameKindCount: Int { activities.activities(of: activity.kind).count }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Name", text: Binding(
                    get: { activity.name },
                    set: { value in activities.update(activity.id) { $0.name = value } }))
                Picker("Counts as", selection: Binding(
                    get: { activity.kind },
                    set: { value in activities.update(activity.id) { $0.kind = value } })) {
                    ForEach(ActivityKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack(spacing: 7) {
                    ForEach(Theme.activityColors, id: \.name) { option in
                        Button { activities.update(activity.id) { $0.color = option.name } } label: {
                            Circle().fill(option.color).frame(width: 16, height: 16)
                                .overlay(Circle().stroke(Color.primary, lineWidth: activity.color == option.name ? 2 : 0).padding(-3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Journal checklist").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(activity.checklist.enumerated()), id: \.offset) { index, _ in
                    HStack(spacing: 6) {
                        TextField("Item", text: Binding(
                            get: { activity.checklist.indices.contains(index) ? activity.checklist[index] : "" },
                            set: { value in
                                activities.update(activity.id) { if $0.checklist.indices.contains(index) { $0.checklist[index] = value } }
                            }))
                        Button {
                            activities.update(activity.id) { if $0.checklist.indices.contains(index) { $0.checklist.remove(at: index) } }
                        } label: {
                            Image(systemName: "xmark").font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                TextField("Add an item", text: $draft.newItem)
                    .onSubmit(addItem)
                Button("Remove activity", role: .destructive) { activities.remove(activity.id) }
                    .disabled(sameKindCount <= 1)
                Text(sameKindCount <= 1
                     ? "Keep at least one \(activity.kind.label.lowercased()) activity."
                     : "Past sessions keep this name in your ledger.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Theme.activityColor(activity.color)).frame(width: 8, height: 8)
                Text(activity.name)
                Spacer()
                Text(activity.kind.label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func addItem() {
        let text = draft.newItem.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        activities.update(activity.id) { $0.checklist.append(text) }
        draft.newItem = ""
    }
}

struct SettingsView: View {
    @ObservedObject var m: TimerModel
    @ObservedObject var settings: AppSettings
    let bridge: FocusBridge
    @ObservedObject var activities: ActivityStore
    @StateObject private var ui = SettingsUI()
    var height: CGFloat = 760

    var body: some View {
        Form {
            Section("Activities") {
                ForEach(activities.activities) { activity in
                    ActivityRow(activities: activities, activity: activity)
                }
                Button("Add activity") { activities.add() }
                Text("Quiz, reading, walks, whatever you track. Sessions keep the name they were logged under, so renaming or removing an activity never changes your history.")
                    .font(.caption).foregroundStyle(.secondary)
            }

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
