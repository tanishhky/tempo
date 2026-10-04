import AppKit
import SwiftUI

// Renders the README images into docs/ from the real PanelView. Run tools/screenshots.sh.

@MainActor
func snapshot<V: View>(_ view: V, dark: Bool, settle: TimeInterval = 1.0, prepare: () -> Void = {}) -> NSImage {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let host = NSHostingView(rootView: view)
    host.appearance = appearance
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = appearance
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    prepare()
    RunLoop.main.run(until: Date().addingTimeInterval(settle))  // let animations and charts settle
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    let image = NSImage(size: host.bounds.size)
    image.addRepresentation(rep)
    return image
}

func save(_ image: NSImage, _ name: String) {
    let rep = image.representations.first as! NSBitmapImageRep
    let data = name.hasSuffix(".jpg")
        ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
        : rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(CommandLine.arguments[1])/\(name)"))
    print("wrote docs/\(name)", rep.pixelsWide, "x", rep.pixelsHigh)
}

let wallpaper = LinearGradient(
    colors: [Color(red: 0.26, green: 0.22, blue: 0.79), Color(red: 0.49, green: 0.23, blue: 0.93), Color(red: 0.75, green: 0.15, blue: 0.83)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

struct PanelCard: View {
    let image: NSImage
    var body: some View {
        Image(nsImage: image)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 28, y: 14)
    }
}

struct MenuPill: View {
    let image: NSImage
    var highlighted = false
    var body: some View {
        Image(nsImage: image)
            .renderingMode(.template)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(highlighted ? 0.24 : 0)))
    }
}

struct Hero: View {
    let panel: NSImage
    let label: NSImage
    var body: some View {
        ZStack(alignment: .top) {
            wallpaper
            RadialGradient(colors: [Color.white.opacity(0.22), .clear], center: .init(x: 0.2, y: 0.1), startRadius: 0, endRadius: 600)
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    Image(systemName: "applelogo").font(.system(size: 15, weight: .medium))
                    Text("Tempo").font(.system(size: 13, weight: .bold))
                    Spacer()
                    MenuPill(image: label, highlighted: true)
                    Image(systemName: "wifi").font(.system(size: 13, weight: .medium))
                    Image(systemName: "battery.75percent").font(.system(size: 15))
                    Text("Mon 9:41 AM").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 32)
                .background(Color.black.opacity(0.18))
                HStack {
                    Spacer()
                    PanelCard(image: panel).padding(.trailing, 81)
                }
            }
        }
        .frame(width: 980, height: 620)
    }
}

struct States: View {
    let panels: [(NSImage, String)]
    var body: some View {
        HStack(alignment: .top, spacing: 36) {
            ForEach(Array(panels.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 22) {
                    PanelCard(image: item.0)
                    Text(item.1).font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.top, 44)
        .padding(.bottom, 34)
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
    }
}

struct MenuBarStrip: View {
    let items: [(NSImage, String)]
    var body: some View {
        HStack(spacing: 44) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 12) {
                    MenuPill(image: item.0)
                        .frame(height: 30)
                        .padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    Text(item.1).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
    }
}

@main
enum Screenshots {
    /// Deterministic fake history so no real study data ever lands in an image.
    @MainActor
    static func sampleHistory() -> [Session] {
        var seed: UInt64 = 42
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        let topics = ["Stochastic calculus", "Options pricing", "Linear algebra", "Probability", "Python and pandas"]
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var out: [Session] = []
        for back in stride(from: 300, through: 0, by: -1) {
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            let weekend = cal.isDateInWeekend(day)
            let ramp = 0.45 + 0.5 * (1 - Double(back) / 300)      // more consistent over time
            if back > 6 && rnd() > (weekend ? ramp * 0.55 : ramp) { continue }
            let blocks = back == 0 ? 2 : (back <= 6 ? 3 : 1 + Int(rnd() * (weekend ? 2.2 : 3.6)))
            var clock = cal.date(byAdding: .hour, value: 9 + Int(rnd() * 4), to: day)!
            for b in 0..<blocks {
                let focus = back == 0 ? 50.0 : [25.0, 50.0, 50.0, 90.0][Int(rnd() * 4)]
                let topic = topics[(back / 9 + b) % topics.count]
                let end = clock.addingTimeInterval(focus * 60)
                out.append(Session(start: clock, end: end, minutes: focus, phase: .focus, topic: topic, completed: back == 0 || rnd() > 0.1))
                let rest = focus >= 50 ? 10.0 : 5.0
                out.append(Session(start: end, end: end.addingTimeInterval(rest * 60), minutes: rest, phase: .rest, topic: "", completed: true))
                clock = end.addingTimeInterval((rest + 20) * 60)
            }
        }
        return out
    }

    @MainActor
    static func main() {
        _ = NSApplication.shared
        let m = TimerModel.shared
        m.store.load(sampleHistory())
        m.focusMinutes = 50
        m.restMinutes = 10
        m.settings.dailyGoalMinutes = 120

        func panel(dark: Bool, _ setup: @escaping () -> Void) -> NSImage {
            snapshot(PanelView(m: m, store: m.store, settings: m.settings, bridge: m.bridge)
                .background(Color(nsColor: .windowBackgroundColor)), dark: dark, prepare: setup)
        }

        let focusing = panel(dark: false) {
            m.stage(phase: .focus, remaining: 1961, running: true, topic: "Options pricing")
        }
        let heroLabel = m.labelImage
        save(snapshot(Hero(panel: focusing, label: heroLabel), dark: false), "hero.jpg")

        let ready = panel(dark: true) { m.stage(phase: .focus, remaining: 3000, running: false, topic: "") }
        let paused = panel(dark: true) { m.stage(phase: .focus, remaining: 1100, running: false, paused: true, topic: "Linear algebra") }
        let pausedLabel = m.labelImage
        let rest = panel(dark: true) { m.stage(phase: .rest, remaining: 432, running: true, topic: "Linear algebra") }
        let restLabel = m.labelImage
        save(snapshot(States(panels: [(ready, "Ready"), (paused, "Paused"), (rest, "Break")]), dark: true), "states.png")

        let idleLabel = MenuBarLabel.render(symbol: "timer", text: nil)
        save(snapshot(MenuBarStrip(items: [(idleLabel, "Idle"), (heroLabel, "Focus"), (pausedLabel, "Paused"), (restLabel, "Break")]), dark: true), "menubar.png")

        m.stage(phase: .focus, remaining: 3000, running: false, topic: "")
        save(snapshot(LedgerView(store: m.store, settings: m.settings, height: 1010), dark: false, settle: 2.0), "ledger.png")
        save(snapshot(LedgerView(store: m.store, settings: m.settings, height: 1010), dark: true, settle: 2.0), "ledger-dark.png")
        save(snapshot(SettingsView(m: m, settings: m.settings, bridge: m.bridge, height: 1000), dark: false, settle: 1.0), "settings.png")
    }
}
