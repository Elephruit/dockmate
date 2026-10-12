import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let scroll = ScrollController()
    private let displays = DisplayController()
    private let defaults = UserDefaults.standard
    private let panel = DockPanel()
    private let popover = NSPopover()

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
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        popover.behavior = .transient
        popover.contentViewController = panel
        panel.onScroll = { [weak self] in self?.toggleScroll() }
        panel.onDisplay = { [weak self] in self?.toggleDisplay() }
        panel.onKeepOff = { [weak self] in self?.keepDisplayOff() }
        panel.onAccessibility = { [weak self] in self?.accessibility() }
        panel.onRecovery = { [weak self] in self?.recoveryError() }
        panel.onLogin = { [weak self] in self?.toggleLogin() }
        panel.onLoginSettings = { [weak self] in self?.loginSettings() }
        panel.onAbout = { [weak self] in self?.about() }
        panel.onQuit = { [weak self] in self?.quit() }
        displays.onChange = { [weak self] in self?.refreshPanel() }
        scroll.onChange = { [weak self] in self?.refreshPanel() }
        displays.start()
        if defaults.bool(forKey: "reverseMouse") { scroll.start(prompt: false) }
        refreshPanel()
    }

    @objc private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        if defaults.bool(forKey: "reverseMouse") && !scroll.isRunning { scroll.start(prompt: false) }
        refreshPanel()
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func refreshPanel() {
        let canRestore = displays.disabledByApp || (!displays.builtInActive && displays.builtInID != nil)
        panel.update(PanelState(
            externalCount: displays.externalCount,
            reverseMouse: defaults.bool(forKey: "reverseMouse"),
            scrollRunning: scroll.isRunning,
            builtInOn: displays.builtInActive,
            displayAvailable: displays.isSupported && displays.builtInID != nil,
            canChangeDisplay: canRestore || (displays.isSupported && displays.builtInActive && displays.externalCount > 0),
            confirmingDisplay: displays.awaitingConfirmation,
            recoveryError: displays.lastError,
            launchAtLogin: SMAppService.mainApp.status == .enabled,
            loginNeedsApproval: SMAppService.mainApp.status == .requiresApproval
        ))
        popover.contentSize = panel.preferredContentSize
        statusItem.button?.toolTip = displays.lastError ?? "DockMate — mouse & monitors"
    }

    @objc private func toggleScroll() {
        if defaults.bool(forKey: "reverseMouse") {
            defaults.set(false, forKey: "reverseMouse")
            scroll.stop()
        } else {
            defaults.set(true, forKey: "reverseMouse")
            if !scroll.start(prompt: true) {
                alert("Allow mouse scroll control", "Enable DockMate in System Settings → Privacy & Security → Accessibility. Then reopen DockMate. If macOS requests it, quit and reopen DockMate.")
            }
        }
        refreshPanel()
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
        refreshPanel()
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
        refreshPanel()
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
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--preview-panel") {
    guard CommandLine.arguments.count > index + 1 else {
        fputs("Usage: DockMate --preview-panel <output-directory>\n", stderr)
        exit(1)
    }
    do { try renderPanelPreviews(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--restore-display") {
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
