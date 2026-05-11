import AppKit
import CryptoKit
import Foundation

struct ClipPut: Codable {
    let text: String
    let device: String
    let hash: String
}

struct ClipState: Codable {
    let text: String
    let device: String
    let hash: String
    let updated_at: Double
}

struct DeviceHeartbeat: Codable {
    let local_paused: Bool
}

struct DeviceState: Codable {
    let device: String
    let enabled: Bool
    let local_paused: Bool
    let last_seen_at: Double
}

struct EncryptedEnvelope: Codable {
    let v: Int
    let alg: String
    let data: String
}

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    var server: String {
        get { defaults.string(forKey: "server") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forKey: "server") }
    }

    var token: String {
        get { defaults.string(forKey: "token") ?? "" }
        set { defaults.set(newValue, forKey: "token") }
    }

    var room: String {
        get { defaults.string(forKey: "room") ?? "home" }
        set { defaults.set(newValue.isEmpty ? "home" : newValue, forKey: "room") }
    }

    var secret: String {
        get { defaults.string(forKey: "secret") ?? "" }
        set { defaults.set(newValue, forKey: "secret") }
    }

    var paused: Bool {
        get { defaults.bool(forKey: "paused") }
        set { defaults.set(newValue, forKey: "paused") }
    }
}

enum CryptoBox {
    static func sha(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func encrypt(_ plaintext: String, secret: String) throws -> String {
        guard !secret.isEmpty else { return plaintext }
        let key = SymmetricKey(data: Data(SHA256.hash(data: Data(secret.utf8))))
        let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key)
        guard let combined = sealed.combined else {
            throw NSError(domain: "ClipMate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to build encrypted payload"])
        }
        let envelope = EncryptedEnvelope(v: 1, alg: "AES-256-GCM-SHA256", data: combined.base64EncodedString())
        let encoded = try JSONEncoder().encode(envelope)
        return String(data: encoded, encoding: .utf8) ?? plaintext
    }

    static func decrypt(_ payload: String, secret: String) throws -> String {
        guard !secret.isEmpty else { return payload }
        guard let data = payload.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(EncryptedEnvelope.self, from: data),
              envelope.v == 1,
              envelope.alg == "AES-256-GCM-SHA256",
              let combined = Data(base64Encoded: envelope.data) else {
            throw NSError(domain: "ClipMate", code: 2, userInfo: [NSLocalizedDescriptionKey: "Encrypted payload requires the same secret"])
        }
        let key = SymmetricKey(data: Data(SHA256.hash(data: Data(secret.utf8))))
        let box = try AES.GCM.SealedBox(combined: combined)
        let opened = try AES.GCM.open(box, using: key)
        return String(data: opened, encoding: .utf8) ?? ""
    }
}

final class RelayClient {
    private let settings = Settings.shared
    let device = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

    private func request<T: Decodable>(_ method: String, _ path: String, body: Data? = nil) async throws -> T? {
        guard !settings.server.isEmpty, !settings.token.isEmpty, let url = URL(string: settings.server + path) else {
            throw NSError(domain: "ClipMate", code: 3, userInfo: [NSLocalizedDescriptionKey: "Open Settings first"])
        }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = method
        request.setValue("Bearer \(settings.token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "ClipMate", code: 4, userInfo: [NSLocalizedDescriptionKey: "Relay request failed"])
        }
        if data.isEmpty || String(data: data, encoding: .utf8) == "null" { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    func heartbeat(paused: Bool) async throws -> DeviceState? {
        let body = try JSONEncoder().encode(DeviceHeartbeat(local_paused: paused))
        return try await request("POST", "/v1/rooms/\(escaped(settings.room))/devices/\(escaped(device))/heartbeat", body: body)
    }

    func pull() async throws -> ClipState? {
        try await request("GET", "/v1/rooms/\(escaped(settings.room))/clip")
    }

    func push(text: String) async throws {
        let payload = try CryptoBox.encrypt(text, secret: settings.secret)
        let put = ClipPut(text: payload, device: device, hash: CryptoBox.sha(payload))
        let body = try JSONEncoder().encode(put)
        let _: ClipState? = try await request("PUT", "/v1/rooms/\(escaped(settings.room))/clip", body: body)
    }
}

final class SyncEngine {
    private let client = RelayClient()
    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastSeen = ""
    private var lastAppliedRemote = ""
    var statusChanged: ((String) -> Void)?

    func start() {
        lastSeen = CryptoBox.sha(pasteboard.string(forType: .string) ?? "")
        timer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        Task { @MainActor in
            do {
                let state = try await client.heartbeat(paused: Settings.shared.paused)
                if Settings.shared.paused {
                    statusChanged?("Paused")
                    return
                }
                if state?.enabled == false {
                    statusChanged?("Disabled by relay")
                    return
                }

                let local = pasteboard.string(forType: .string) ?? ""
                let localHash = CryptoBox.sha(local)
                if !local.isEmpty, localHash != lastSeen, localHash != lastAppliedRemote {
                    try await client.push(text: local)
                    lastSeen = localHash
                }

                if let remote = try await client.pull(), remote.device != client.device {
                    let remoteText = try CryptoBox.decrypt(remote.text, secret: Settings.shared.secret)
                    let remoteHash = CryptoBox.sha(remoteText)
                    if !remoteText.isEmpty, remoteHash != CryptoBox.sha(pasteboard.string(forType: .string) ?? "") {
                        pasteboard.clearContents()
                        pasteboard.setString(remoteText, forType: .string)
                        lastAppliedRemote = remoteHash
                        lastSeen = remoteHash
                    }
                }
                statusChanged?("Connected")
            } catch {
                statusChanged?(error.localizedDescription)
            }
        }
    }
}

final class SettingsWindowController: NSWindowController {
    private let server = NSTextField()
    private let token = NSSecureTextField()
    private let room = NSTextField()
    private let secret = NSSecureTextField()

    init() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 240))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ClipMate Settings"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = view
        build(view)
        load()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build(_ view: NSView) {
        let labels = ["Server", "Token", "Room", "Encryption Secret"]
        let fields: [NSTextField] = [server, token, room, secret]
        for (i, labelText) in labels.enumerated() {
            let y = 185 - (i * 42)
            let label = NSTextField(labelWithString: labelText)
            label.frame = NSRect(x: 24, y: y + 4, width: 130, height: 22)
            fields[i].frame = NSRect(x: 160, y: y, width: 270, height: 26)
            view.addSubview(label)
            view.addSubview(fields[i])
        }
        let save = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        save.frame = NSRect(x: 334, y: 18, width: 96, height: 32)
        view.addSubview(save)
    }

    private func load() {
        server.stringValue = Settings.shared.server
        token.stringValue = Settings.shared.token
        room.stringValue = Settings.shared.room
        secret.stringValue = Settings.shared.secret
    }

    @objc private func saveSettings() {
        Settings.shared.server = server.stringValue
        Settings.shared.token = token.stringValue
        Settings.shared.room = room.stringValue
        Settings.shared.secret = secret.stringValue
        window?.close()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let engine = SyncEngine()
    private var status = "Starting"
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        statusItem.button?.title = "CM"
        rebuildMenu()
        engine.statusChanged = { [weak self] status in
            DispatchQueue.main.async {
                self?.status = status
                self?.statusItem.button?.title = status == "Connected" ? "CM" : "CM"
                self?.rebuildMenu()
            }
        }
        engine.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.openSettings()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        openSettings()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Status: \(status)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Room: \(Settings.shared.room)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let pauseTitle = Settings.shared.paused ? "Resume Sync" : "Pause Sync"
        menu.addItem(NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func togglePause() {
        Settings.shared.paused.toggle()
        rebuildMenu()
    }

    @objc private func openSettings() {
        settingsWindow = settingsWindow ?? SettingsWindowController()
        settingsWindow?.window?.center()
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        settingsWindow?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        engine.stop()
        NSApp.terminate(nil)
    }
}
