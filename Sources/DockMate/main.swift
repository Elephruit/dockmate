import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let scroll = ScrollController()
    private let displays = DisplayController()
    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "display", accessibilityDescription: "DockMate")
        image?.size = NSSize(width: 20, height: 20)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "DockMate — mouse & monitors"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        displays.onChange = { [weak self] in self?.refreshMenu() }
        scroll.onChange = { [weak self] in self?.refreshMenu() }
        displays.start()
        if defaults.bool(forKey: "reverseMouse") { scroll.start(prompt: false) }
        refreshMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if defaults.bool(forKey: "reverseMouse") && !scroll.isRunning { scroll.start(prompt: false) }
        refreshMenu()
    }

    private func item(_ title: String, action: Selector? = nil, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    private func refreshMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.autoenablesItems = false
        menu.removeAllItems()
        menu.addItem(item("DockMate", enabled: false))
        menu.addItem(item("\(displays.externalCount) external monitor\(displays.externalCount == 1 ? "" : "s") connected", enabled: false))
        menu.addItem(.separator())
        let reverse = item("Reverse Mouse Scrolling", action: #selector(toggleScroll))
        reverse.state = scroll.isRunning ? .on : .off
        menu.addItem(reverse)
        menu.addItem(item("Wheel mice only · trackpad unchanged", enabled: false))
        if defaults.bool(forKey: "reverseMouse") && !scroll.isRunning {
            menu.addItem(item("Allow Accessibility to enable scrolling…", action: #selector(accessibility)))
        }
        menu.addItem(.separator())
        let canRestore = displays.disabledByApp || (!displays.builtInActive && displays.builtInID != nil)
        menu.addItem(item(canRestore ? "Turn Built-in Display On" : "Turn Built-in Display Off…",
                          action: #selector(toggleDisplay),
                          enabled: canRestore || (displays.isSupported && displays.builtInActive && displays.externalCount > 0)))
        if displays.awaitingConfirmation {
            menu.addItem(item("Keep Built-in Display Off", action: #selector(keepDisplayOff)))
            menu.addItem(item("Restores after 15 seconds unless kept", enabled: false))
        } else if displays.disabledByApp {
            menu.addItem(item("Restores on unplug, sleep, or quit", enabled: false))
        } else if !displays.isSupported {
            menu.addItem(item("Display control unavailable on this macOS", enabled: false))
        } else if displays.externalCount == 0 {
            menu.addItem(item("Connect an external monitor first", enabled: false))
        }
        if let error = displays.lastError {
            menu.addItem(item("Display recovery needs attention…", action: #selector(recoveryError)))
            statusItem.button?.toolTip = error
        } else {
            statusItem.button?.toolTip = "DockMate — mouse & monitors"
        }
        menu.addItem(.separator())
        let login = item("Launch at Login", action: #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        if SMAppService.mainApp.status == .requiresApproval {
            menu.addItem(item("Approve in Login Items…", action: #selector(loginSettings)))
        }
        menu.addItem(item("About DockMate…", action: #selector(about)))
        menu.addItem(item("Quit DockMate", action: #selector(quit)))
    }

    @objc private func toggleScroll() {
        if defaults.bool(forKey: "reverseMouse") && scroll.isRunning {
            defaults.set(false, forKey: "reverseMouse")
            scroll.stop()
        } else if defaults.bool(forKey: "reverseMouse") {
            // An enabled preference with missing permission can still be switched off.
            defaults.set(false, forKey: "reverseMouse")
            scroll.stop()
        } else {
            defaults.set(true, forKey: "reverseMouse")
            if !scroll.start(prompt: true) {
                alert("Allow mouse scroll control", "Enable DockMate in System Settings → Privacy & Security → Accessibility. Then reopen this menu. If macOS requests it, quit and reopen DockMate.")
            }
        }
        refreshMenu()
    }

    @objc private func accessibility() {
        scroll.start(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleDisplay() {
        do {
            if displays.disabledByApp || !displays.builtInActive { try displays.restore() }
            else { try displays.turnOff() }
        } catch { alert("Display change failed", error.localizedDescription) }
        refreshMenu()
    }

    @objc private func keepDisplayOff() { displays.keepOff() }
    @objc private func recoveryError() {
        alert("Display recovery needs attention", displays.lastError ?? "Try turning the built-in display on again.")
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { alert("Could not update Launch at Login", error.localizedDescription) }
        refreshMenu()
    }
    @objc private func loginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func about() {
        alert("DockMate", "A small mouse & monitor utility.\n\nReverse Mouse Scrolling flips your wheel mouse relative to the macOS setting. Trackpads and touch mice (including Magic Mouse) keep their current direction.\n\nDisplay off uses a private macOS API and may vary by OS version. The built-in display restores on unplug, sleep, and quit.")
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do { try displays.stop() } catch {
            alert("Restore the built-in display before quitting", error.localizedDescription)
            return .terminateCancel
        }
        scroll.stop()
        return .terminateNow
    }
    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

if CommandLine.arguments.contains("--restore-display") {
    do {
        try DisplayController().restore()
        print("Built-in display enabled.")
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else if CommandLine.arguments.contains("--diagnose") {
    let displays = DisplayController()
    print("Display API available: \(displays.isSupported)")
    print("Built-in display found: \(displays.builtInID != nil)")
    print("Built-in display active: \(displays.builtInActive)")
    print("Active external monitors: \(displays.externalCount)")
} else {
    // One menu item and one display owner, even if launched twice.
    let identifier = Bundle.main.bundleIdentifier ?? "local.elephruit.DockMate"
    if NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
