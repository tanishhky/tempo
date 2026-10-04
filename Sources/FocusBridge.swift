import Foundation

struct PhoneConfig: Sendable {
    var host: String
    var port: Int
    var token: String
}

struct PhoneReply: Sendable {
    var ok: Bool
    var message: String
    var dndAccess: Bool?
    var dndActive: Bool?
}

/// Switches Do Not Disturb on the Mac (via two Shortcuts) and on a paired Android phone
/// (via the Tempo Companion app on the local network) while a focus block runs.
@MainActor
final class FocusBridge: ObservableObject {
    static let shared = FocusBridge()

    /// True while Tempo has asked a device to stay in Do Not Disturb.
    @Published private(set) var active = false
    @Published private(set) var macProblem: String?
    @Published private(set) var phoneProblem: String?

    private let settings = AppSettings.shared
    private var macArmed = false
    private var phoneArmed = false
    private var macChain: Task<Void, Never>?
    private var phoneChain: Task<Void, Never>?

    var phoneConfig: PhoneConfig {
        PhoneConfig(host: settings.phoneHost.trimmingCharacters(in: .whitespaces),
                    port: settings.phonePort, token: settings.phoneToken.trimmingCharacters(in: .whitespaces))
    }

    /// Idempotent. `on` asks for Do Not Disturb; `ttlMinutes` is the phone's failsafe so it
    /// switches itself back if the Mac never says "off" (crash, sleep, Wi-Fi drop).
    func setActive(_ on: Bool, ttlMinutes: Int) {
        if (on && settings.dndMac) || (!on && macArmed) {
            macArmed = on
            let name = on ? AppSettings.macOnShortcut : AppSettings.macOffShortcut
            macChain = Task { [prev = macChain] in
                await prev?.value
                let error = await Task.detached { Self.runShortcutSync(name) }.value
                self.macProblem = error
            }
        }
        if (on && settings.dndPhone) || (!on && phoneArmed) {
            phoneArmed = on
            let config = phoneConfig
            phoneChain = Task { [prev = phoneChain] in
                await prev?.value
                let reply = await Task.detached { Self.setPhoneSync(config, on: on, ttlMinutes: ttlMinutes) }.value
                self.phoneProblem = reply.ok ? nil : reply.message
            }
        }
        active = macArmed || phoneArmed
    }

    /// Blocking "off" for app quit, so nothing is left in Do Not Disturb.
    func shutdown() {
        if macArmed { _ = Self.runShortcutSync(AppSettings.macOffShortcut) }
        if phoneArmed { _ = Self.setPhoneSync(phoneConfig, on: false, ttlMinutes: 0) }
        macArmed = false
        phoneArmed = false
        active = false
    }

    // MARK: Settings screen helpers

    func macShortcutsStatus() async -> String {
        await Task.detached {
            let (out, status) = Self.run("/usr/bin/shortcuts", ["list"])
            guard status == 0 else { return "Could not read your Shortcuts." }
            let names = Set(out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
            let missing = [AppSettings.macOnShortcut, AppSettings.macOffShortcut].filter { !names.contains($0) }
            return missing.isEmpty ? "Both shortcuts found." : "Missing: " + missing.map { "\"\($0)\"" }.joined(separator: ", ")
        }.value
    }

    func testMac(on: Bool) async -> String {
        let name = on ? AppSettings.macOnShortcut : AppSettings.macOffShortcut
        let error = await Task.detached { Self.runShortcutSync(name) }.value
        return error ?? (on ? "Focus should be on now." : "Focus should be off now.")
    }

    func testPhone() async -> PhoneReply {
        let config = phoneConfig
        return await Task.detached { Self.phoneCallSync(config, path: "/status", method: "GET", body: nil) }.value
    }

    // MARK: Plumbing (blocking, called off the main actor except in shutdown)

    nonisolated static func run(_ launch: String, _ args: [String]) -> (String, Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return ("\(error.localizedDescription)", -1) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), p.terminationStatus)
    }

    nonisolated static func runShortcutSync(_ name: String) -> String? {
        let (out, status) = run("/usr/bin/shortcuts", ["run", name])
        if status == 0 { return nil }
        let text = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Shortcut \"\(name)\" failed." : text
    }

    nonisolated static func setPhoneSync(_ c: PhoneConfig, on: Bool, ttlMinutes: Int) -> PhoneReply {
        phoneCallSync(c, path: "/dnd", method: "POST", body: ["on": on, "ttl_minutes": max(ttlMinutes, 1)])
    }

    nonisolated static func phoneCallSync(_ c: PhoneConfig, path: String, method: String, body: [String: Any]?,
                                          timeout: TimeInterval = 4) -> PhoneReply {
        guard !c.host.isEmpty, let url = URL(string: "http://\(c.host):\(c.port)\(path)") else {
            return PhoneReply(ok: false, message: "Enter the phone's address first.")
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("Bearer \(c.token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        let done = DispatchSemaphore(value: 0)
        var reply = PhoneReply(ok: false, message: "No response from the phone.")
        session.dataTask(with: req) { data, response, error in
            defer { done.signal() }
            if let error {
                let code = (error as NSError).code
                reply.message = code == NSURLErrorTimedOut ? "The phone did not answer. Is it on the same Wi-Fi?"
                    : code == NSURLErrorCannotConnectToHost ? "The companion app is not running on the phone."
                    : error.localizedDescription
                return
            }
            let http = response as? HTTPURLResponse
            let json = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any]
            switch http?.statusCode {
            case 200:
                reply = PhoneReply(ok: true, message: "Connected.", dndAccess: json?["dnd_access"] as? Bool,
                                   dndActive: json?["dnd_active"] as? Bool)
            case 401:
                reply.message = "The phone rejected the token. Copy it again from the companion app."
            case 409:
                reply = PhoneReply(ok: false, message: "Grant Do Not Disturb access to Tempo Companion on the phone.",
                                   dndAccess: false)
            default:
                reply.message = "Unexpected reply from the phone (\(http?.statusCode ?? 0))."
            }
        }.resume()
        if done.wait(timeout: .now() + timeout + 1) == .timedOut { reply.message = "The phone did not answer." }
        session.invalidateAndCancel()
        return reply
    }
}
