import SwiftUI

/// Text behind the length field. Kept as an object because Tempo builds without the @State macro.
final class LengthDraft: ObservableObject {
    @Published var text = ""
}

struct PanelView: View {
    @ObservedObject var m: TimerModel
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var bridge: FocusBridge
    @ObservedObject var activities: ActivityStore
    @StateObject private var length = LengthDraft()
    @Environment(\.openWindow) private var openWindow

    private var accent: Color { m.phase == .focus ? Theme.focus : Theme.rest }
    private var presets: [Int] { m.phase == .focus ? [25, 50, 90] : [5, 10, 20] }
    private var choices: [Activity] { activities.activities(of: m.phase == .focus ? .focus : .rest) }

    private var today: Double { store.ledger.day(Date()).focus }
    private var goal: Double { Double(settings.dailyGoalMinutes) }
    private var streak: Int { store.ledger.streak(goal: goal).current }

    var body: some View {
        VStack(spacing: 16) {
            Picker("", selection: $m.phase) {
                Text("Focus").tag(Phase.focus)
                Text("Break").tag(Phase.rest)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
            .disabled(!m.isIdle)

            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: m.progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(m.progress > 0 ? 1 : 0)
                    .animation(.linear(duration: 0.3), value: m.progress)
                VStack(spacing: 2) {
                    Text(m.clock)
                        .font(.system(size: 46, weight: .light, design: .rounded))
                        .monospacedDigit()
                    HStack(spacing: 4) {
                        if bridge.active { Image(systemName: "moon.fill").font(.caption2) }
                        Text(bridge.active ? "Focusing, DND on" : m.statusLine)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            .frame(width: 196, height: 196)
            .padding(.vertical, 4)

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(presets, id: \.self) { p in
                        Button { m.setMinutes(p) } label: {
                            Text("\(p)")
                                .font(.callout.weight(.medium))
                                .monospacedDigit()
                                .frame(width: 42, height: 26)
                                .background(Capsule().fill(m.minutes == p ? accent.opacity(0.18) : Color.primary.opacity(0.06)))
                                .foregroundStyle(m.minutes == p ? accent : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    roundButton("minus", size: 26) { m.nudge(-1) }
                    TextField("", text: $length.text)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .monospacedDigit()
                        .frame(width: 44, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
                        .onSubmit(commitLength)
                    Text("min").font(.caption).foregroundStyle(.secondary)
                    roundButton("plus", size: 26) { m.nudge(1) }
                }
            }
            .disabled(!m.isIdle)
            .opacity(m.isIdle ? 1 : 0.35)
            .onAppear { length.text = "\(m.minutes)" }
            .onChange(of: m.minutes) { _, value in length.text = "\(value)" }

            activityChips
                .disabled(!m.isIdle)
                .opacity(m.isIdle ? 1 : 0.35)

            TextField("What are you studying?", text: $m.topic)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))

            HStack(spacing: 14) {
                roundButton("arrow.counterclockwise", size: 34) { m.reset() }
                    .keyboardShortcut("r")
                    .help("Reset (⌘R)")
                    .disabled(m.isIdle)
                Button { m.toggle() } label: {
                    Text(m.isRunning ? "Pause" : (m.isPaused ? "Resume" : "Start"))
                        .font(.body.weight(.semibold))
                        .frame(width: 124, height: 34)
                        .background(Capsule().fill(accent))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                roundButton("forward.end", size: 34) { m.skip() }
                    .help(m.phase == .focus ? "Skip to break" : "Skip to focus")
            }

            Divider().padding(.top, 2)

            VStack(spacing: 7) {
                HStack {
                    Text("Today **\(Fmt.minutes(today))** of \(Fmt.minutes(goal))")
                    Spacer()
                    if streak > 0 {
                        Label("\(streak)", systemImage: "flame.fill")
                            .foregroundStyle(Theme.flame)
                            .help("\(streak)-day streak of hitting your daily goal")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(today >= goal ? Theme.rest : Theme.focus)
                            .frame(width: geo.size.width * min(1, today / max(goal, 1)))
                    }
                }
                .frame(height: 4)
            }

            if let problem = bridge.phoneProblem ?? bridge.macProblem {
                Text(problem)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 14) {
                Button("Ledger") { show("ledger") }
                Button("Journal") { show("journal") }
                Button("Settings") { show("settings") }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 300)
        .onAppear { store.reload() }
    }

    /// One chip per activity of the current kind. Tapping one picks what the next block is logged as.
    private var activityChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(choices) { a in
                    let selected = a.id == m.currentActivityID
                    Button { m.setActivity(a.id) } label: {
                        HStack(spacing: 5) {
                            Circle().fill(activities.color(a.id)).frame(width: 7, height: 7)
                            Text(a.name).lineLimit(1)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(selected ? activities.color(a.id).opacity(0.18) : Color.primary.opacity(0.06)))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 26)
    }

    /// Accepts any whole number of minutes. Anything that isn't a number leaves the length unchanged.
    private func commitLength() {
        if let value = Int(length.text.trimmingCharacters(in: .whitespaces)) {
            m.setMinutes(value)
        }
        length.text = "\(m.minutes)"
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func roundButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
