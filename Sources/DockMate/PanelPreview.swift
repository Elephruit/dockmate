import AppKit

/// Render the real panel in representative states without changing preferences,
/// requesting permissions, or touching display hardware.
func renderPanelPreviews(to directory: URL) throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let scenarios: [(String, PanelState)] = [
        ("connected", PanelState(externalCount: 2, reverseMouse: true, scrollRunning: true,
                                 canChangeDisplay: true)),
        ("undocked", PanelState()),
        ("permission", PanelState(externalCount: 1, reverseMouse: true, canChangeDisplay: true)),
        ("trial", PanelState(externalCount: 1, reverseMouse: true, scrollRunning: true,
                             builtInOn: false, canChangeDisplay: true, confirmingDisplay: true)),
        ("recovery", PanelState(externalCount: 1, builtInOn: false, canChangeDisplay: true,
                                recoveryError: "Recovery failed", loginNeedsApproval: true)),
        ("unsupported", PanelState(displayAvailable: false))
    ]
    for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        for (name, state) in scenarios {
            let panel = DockPanel()
            panel.view.appearance = NSAppearance(named: appearance)
            panel.update(state)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: panel.preferredContentSize),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentViewController = panel
            window.backgroundColor = .windowBackgroundColor
            panel.update(state)
            window.setContentSize(panel.preferredContentSize)
            panel.view.layoutSubtreeIfNeeded()
            guard let bitmap = panel.view.bitmapImageRepForCachingDisplay(in: panel.view.bounds) else {
                throw Failure("Could not create panel preview.")
            }
            panel.view.cacheDisplay(in: panel.view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw Failure("Could not encode panel preview.")
            }
            try data.write(to: directory.appendingPathComponent("\(name)-\(theme).png"))
            print("\(name)-\(theme): \(Int(panel.preferredContentSize.width)) × \(Int(panel.preferredContentSize.height))")
        }
    }
}
