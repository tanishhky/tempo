import SwiftUI
import UserNotifications

@main
struct TempoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = TimerModel.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView(m: model, store: model.store, settings: model.settings, bridge: model.bridge,
                      activities: model.activities)
        } label: {
            MenuLabel(m: model)
        }
        .menuBarExtraStyle(.window)

        Window("Tempo Ledger", id: "ledger") {
            LedgerView(store: model.store, settings: model.settings, activities: model.activities)
        }
        .windowResizability(.contentSize)

        Window("Tempo Journal", id: "journal") {
            JournalView(journal: JournalStore.shared, activities: model.activities)
        }
        .windowResizability(.contentSize)

        Window("Tempo Settings", id: "settings") {
            SettingsView(m: model, settings: model.settings, bridge: model.bridge, activities: model.activities)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuLabel: View {
    @ObservedObject var m: TimerModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: m.labelImage)
            .onChange(of: m.windowRequest) { _, id in
                guard let id else { return }
                openWindow(id: id)
                NSApp.activate(ignoringOtherApps: true)
                m.windowRequest = nil
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // The MCP server and other tools write these files while Tempo runs. Re-read them when Tempo comes forward.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                SessionStore.shared.reload()
                ActivityStore.shared.reload()
                JournalStore.shared.reload()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { TimerModel.shared.handle($0) }
    }

    /// Never leave a device in Do Not Disturb because Tempo quit.
    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        FocusBridge.shared.shutdown()
    }

    // Show the banner even while the panel is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
