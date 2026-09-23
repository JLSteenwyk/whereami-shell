// WhereAmI menu bar app for whereami-shell.
//
// Shows this Mac's configured color in the menu bar and lets you enable or
// disable whereami (window tint and optional prompt label). The toggle simply
// creates or removes ~/.config/whereami/disabled, which whereami.sh checks on
// every prompt, so every open terminal reacts immediately.
//
// Build:  make app      (single-file swiftc build, no Xcode project)

import Cocoa
import ServiceManagement

// MARK: - Paths and config (mirrors whereami.sh)

struct Paths {
    static var configFile: URL {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["WHEREAMI_CONFIG"], !explicit.isEmpty {
            return URL(fileURLWithPath: explicit)
        }
        let base = env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? NSHomeDirectory() + "/.config"
        return URL(fileURLWithPath: base).appendingPathComponent("whereami/config")
    }
    static var configDir: URL { configFile.deletingLastPathComponent() }
    static var disabledFlag: URL { configDir.appendingPathComponent("disabled") }
}

struct Config {
    var name: String
    var color: String

    static func load() -> Config {
        var name = "", color = ""
        if let text = try? String(contentsOf: Paths.configFile, encoding: .utf8) {
            for raw in text.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                guard let eq = line.firstIndex(of: "=") else { continue }
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if key == "name" { name = value }
                if key == "color" { color = value }
            }
        }
        if name.isEmpty { name = shortHostname() }
        if color.isEmpty { color = defaultColor(for: name) }
        return Config(name: name, color: color)
    }

    /// Same value as `hostname -s` (ProcessInfo.hostName lowercases it, which
    /// would change the derived color relative to the shell).
    static func shortHostname() -> String {
        var buf = [CChar](repeating: 0, count: 256)
        let full = gethostname(&buf, buf.count) == 0 ? String(cString: buf) : ProcessInfo.processInfo.hostName
        return String(full.split(separator: ".").first ?? Substring(full))
    }

    /// Same hash as whereami_default_color in whereami.sh.
    static func defaultColor(for name: String) -> String {
        let palette = ["red", "green", "yellow", "blue", "magenta", "cyan"]
        var sum = 0
        for scalar in name.unicodeScalars { sum = (sum * 31 + Int(scalar.value)) % 6 }
        return palette[sum]
    }
}

// MARK: - Colors

enum Palette {
    static func nsColor(_ spec: String) -> NSColor? {
        let named: [String: NSColor] = [
            "black": .black, "red": .systemRed, "green": .systemGreen,
            "yellow": .systemYellow, "blue": .systemBlue, "magenta": .systemPink,
            "cyan": .systemTeal, "white": .white,
        ]
        if let c = named[spec] { return c }
        if spec.hasPrefix("bright-"), let c = named[String(spec.dropFirst(7))] {
            return c.blended(withFraction: 0.25, of: .white) ?? c
        }
        if let n = Int(spec), (0...255).contains(n) { return xterm256(n) }
        return nil
    }

    static func xterm256(_ n: Int) -> NSColor {
        func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
            NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        }
        let basic = [
            (0,0,0),(205,0,0),(0,205,0),(205,205,0),(0,0,238),(205,0,205),(0,205,205),(229,229,229),
            (127,127,127),(255,0,0),(0,255,0),(255,255,0),(92,92,255),(255,0,255),(0,255,255),(255,255,255),
        ]
        if n < 16 { let c = basic[n]; return rgb(c.0, c.1, c.2) }
        if n < 232 {
            let i = n - 16
            let steps = [0, 95, 135, 175, 215, 255]
            return rgb(steps[i / 36], steps[(i / 6) % 6], steps[i % 6])
        }
        let g = 8 + (n - 232) * 10
        return rgb(g, g, g)
    }
}

// MARK: - Outgoing SSH sessions from this Mac

enum SSHSessions {
    /// Hosts of `ssh` client processes currently running on this Mac.
    static func active() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "args="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var hosts: [String] = []
        for line in text.split(separator: "\n") {
            let words = line.split(separator: " ").map(String.init)
            guard let cmd = words.first, (cmd as NSString).lastPathComponent == "ssh" else { continue }
            if let host = destination(of: Array(words.dropFirst())), !hosts.contains(host) {
                hosts.append(host)
            }
        }
        return hosts
    }

    /// First non-option argument, i.e. the [user@]host, skipping option values.
    private static func destination(of args: [String]) -> String? {
        let takesValue: Set<Character> = ["b", "c", "D", "E", "e", "F", "I", "i", "J", "L", "l",
                                          "m", "O", "o", "p", "Q", "R", "S", "W", "w", "B"]
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--" { return args.count > i + 1 ? args[i + 1] : nil }
            if a.hasPrefix("-"), a.count >= 2 {
                let flag = a[a.index(after: a.startIndex)]
                if takesValue.contains(flag) && a.count == 2 { i += 2 } else { i += 1 }
                continue
            }
            if a.hasPrefix("ssh://") { return String(a.dropFirst(6)) }
            // `ps` output loses quoting, so an option value containing a space
            // (e.g. -o "ProxyCommand=nc %h") leaks stray words. Accept only
            // tokens that look like a host: [user@]name with a letter or a dot.
            if looksLikeHost(a) { return a }
            i += 1
        }
        return nil
    }

    private static func looksLikeHost(_ token: String) -> Bool {
        let host = token.split(separator: "@").last.map(String.init) ?? token
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_:[]%"))
        guard !host.isEmpty, host.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        return host.contains(".") || host.contains(where: { $0.isLetter })
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let nameItem = NSMenuItem()
    private let hostItem = NSMenuItem()
    private let promptItem = NSMenuItem()
    private let sshHeaderItem = NSMenuItem()
    private var sshItems: [NSMenuItem] = []
    private let toggleItem = NSMenuItem(title: "Enabled on this Mac", action: #selector(togglePrompt), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Start at login", action: #selector(toggleLogin), keyEquivalent: "")
    private var watcher: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        menu.delegate = self

        for item in [nameItem, hostItem, promptItem] { item.isEnabled = false; menu.addItem(item) }
        menu.addItem(.separator())
        sshHeaderItem.isEnabled = false
        menu.addItem(sshHeaderItem)
        menu.addItem(.separator())
        toggleItem.target = self
        menu.addItem(toggleItem)
        let edit = NSMenuItem(title: "Edit config…", action: #selector(editConfig), keyEquivalent: ",")
        edit.target = self
        menu.addItem(edit)
        menu.addItem(.separator())
        loginItem.target = self
        menu.addItem(loginItem)
        let quit = NSMenuItem(title: "Quit WhereAmI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        try? FileManager.default.createDirectory(at: Paths.configDir, withIntermediateDirectories: true)
        startWatching()
        // Fallback poll: catches in-place edits that do not touch the directory.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher?.cancel()
    }

    // MARK: State

    private var isEnabled: Bool {
        !FileManager.default.fileExists(atPath: Paths.disabledFlag.path)
    }

    @objc private func refresh() {
        let config = Config.load()
        let enabled = isEnabled
        let color = Palette.nsColor(config.color) ?? Palette.nsColor(Config.defaultColor(for: config.name))!

        // Menu bar: one small icon, tinted with the machine color; gray when off.
        let tint = enabled ? color : NSColor.tertiaryLabelColor
        let base = NSImage(systemSymbolName: "terminal", accessibilityDescription: "whereami-shell")
            ?? NSImage(systemSymbolName: "display", accessibilityDescription: nil)!
        let configured = base.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))) ?? base
        configured.isTemplate = false
        statusItem.button?.image = configured
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "\(config.name) · whereami \(enabled ? "on" : "off")"

        // Menu contents
        nameItem.attributedTitle = NSAttributedString(string: config.name, attributes: [
            .foregroundColor: color, .font: NSFont.boldSystemFont(ofSize: 14),
        ])
        hostItem.title = "Host: \(Config.shortHostname())   Color: \(config.color)"
        promptItem.title = "Window tint: \(enabled ? "on" : "off")"
        toggleItem.state = enabled ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        let hosts = SSHSessions.active()
        sshHeaderItem.title = hosts.isEmpty ? "No SSH sessions from this Mac" : "SSH sessions from this Mac"
        for item in sshItems { menu.removeItem(item) }
        sshItems = hosts.map { host in
            let item = NSMenuItem(title: "→ \(host)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.indentationLevel = 1
            return item
        }
        var index = menu.index(of: sshHeaderItem) + 1
        for item in sshItems { menu.insertItem(item, at: index); index += 1 }
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    // MARK: Actions

    @objc private func togglePrompt() {
        let fm = FileManager.default
        if isEnabled {
            fm.createFile(atPath: Paths.disabledFlag.path, contents: Data())
        } else {
            try? fm.removeItem(at: Paths.disabledFlag)
        }
        refresh()
    }

    @objc private func editConfig() {
        let file = Paths.configFile
        if !FileManager.default.fileExists(atPath: file.path) {
            let c = Config.load()
            try? "name=\(c.name)\ncolor=\(c.color)\n".write(to: file, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(file)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refresh()
    }

    // MARK: File watching

    private func startWatching() {
        watchedFD = open(Paths.configDir.path, O_EVTONLY)
        guard watchedFD >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watchedFD, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.refresh() }
        source.setCancelHandler { [fd = watchedFD] in close(fd) }
        source.resume()
        watcher = source
    }
}

// Debug aid: `WhereAmI --sessions` prints the detected SSH hosts and exits.
if CommandLine.arguments.contains("--sessions") {
    for host in SSHSessions.active() { print(host) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
