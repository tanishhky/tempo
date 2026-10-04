import AppKit
import SwiftUI

// Renders the README images into docs/ from the real PanelView. Run tools/screenshots.sh.

@MainActor
func snapshot<V: View>(_ view: V, dark: Bool, prepare: () -> Void = {}) -> NSImage {
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
    RunLoop.main.run(until: Date().addingTimeInterval(1.0))  // let the ring animation settle
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
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let m = TimerModel.shared
        m.focusMinutes = 50
        m.restMinutes = 10
        let stats = (today: 2.5 * 3600.0, sessions: 3, week: 14 * 3600.0 + 600)
        func panel(dark: Bool, _ setup: @escaping () -> Void) -> NSImage {
            snapshot(PanelView(m: m).background(Color(nsColor: .windowBackgroundColor)), dark: dark, prepare: setup)
        }

        let focusing = panel(dark: false) {
            m.stage(phase: .focus, remaining: 1961, running: true, topic: "Options pricing, ch. 7",
                    today: stats.today, sessions: stats.sessions, week: stats.week)
        }
        let heroLabel = m.labelImage
        save(snapshot(Hero(panel: focusing, label: heroLabel), dark: false), "hero.jpg")

        let ready = panel(dark: true) {
            m.stage(phase: .focus, remaining: 3000, running: false, topic: "",
                    today: stats.today, sessions: stats.sessions, week: stats.week)
        }
        let paused = panel(dark: true) {
            m.stage(phase: .focus, remaining: 1100, running: false, paused: true, topic: "Linear algebra problem set",
                    today: stats.today, sessions: stats.sessions, week: stats.week)
        }
        let pausedLabel = m.labelImage
        let rest = panel(dark: true) {
            m.stage(phase: .rest, remaining: 432, running: true, topic: "Linear algebra problem set",
                    today: stats.today + 1800, sessions: 4, week: stats.week + 1800)
        }
        let restLabel = m.labelImage
        save(snapshot(States(panels: [(ready, "Ready"), (paused, "Paused"), (rest, "Break")]), dark: true), "states.png")

        let idleLabel = MenuBarLabel.render(symbol: "timer", text: nil)
        save(snapshot(MenuBarStrip(items: [(idleLabel, "Idle"), (heroLabel, "Focus"), (pausedLabel, "Paused"), (restLabel, "Break")]), dark: true), "menubar.png")
    }
}
