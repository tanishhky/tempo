import SwiftUI

struct PanelView: View {
    @ObservedObject var m: TimerModel

    private var accent: Color {
        m.phase == .focus ? Color(red: 0.40, green: 0.40, blue: 0.95) : Color(red: 0.08, green: 0.66, blue: 0.60)
    }
    private var presets: [Int] { m.phase == .focus ? [25, 50, 90] : [5, 10, 20] }

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
                    .animation(.linear(duration: 0.3), value: m.progress)
                VStack(spacing: 2) {
                    Text(m.clock)
                        .font(.system(size: 46, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text(m.statusLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 150)
                }
            }
            .frame(width: 196, height: 196)
            .padding(.vertical, 4)

            HStack(spacing: 6) {
                roundButton("minus", size: 26) { m.nudge(-5) }
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
                roundButton("plus", size: 26) { m.nudge(5) }
            }
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

            HStack {
                Text("Today **\(duration(m.todaySeconds))** · \(m.todaySessions) done")
                Spacer()
                Text("7 days **\(duration(m.weekSeconds))**")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Toggle("Open at login", isOn: Binding(get: { m.launchAtLogin }, set: { m.setLaunchAtLogin($0) }))
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .keyboardShortcut("q")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 300)
        .onAppear { m.loadStats() }
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

    private func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds / 60)
        let h = total / 60, m = total % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
