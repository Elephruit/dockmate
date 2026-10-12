import AppKit

struct PanelState {
    var externalCount = 0
    var reverseMouse = false
    var scrollRunning = false
    var builtInOn = true
    var displayAvailable = true
    var canChangeDisplay = false
    var confirmingDisplay = false
    var recoveryError: String?
    var launchAtLogin = false
    var loginNeedsApproval = false
}

/// Native AppKit controls keep the popover small and respect macOS appearance,
/// keyboard navigation, and accessibility settings.
final class DockPanel: NSViewController {
    var onScroll: (() -> Void)?
    var onDisplay: (() -> Void)?
    var onKeepOff: (() -> Void)?
    var onAccessibility: (() -> Void)?
    var onRecovery: (() -> Void)?
    var onLogin: (() -> Void)?
    var onLoginSettings: (() -> Void)?
    var onAbout: (() -> Void)?
    var onQuit: (() -> Void)?

    private let column = NSStackView()
    private let connection = DockPanel.label("", size: 11, color: .secondaryLabelColor)
    private let mouseSwitch = NSSwitch()
    private let displaySwitch = NSSwitch()
    private let mouseDetail = DockPanel.label("Trackpad stays unchanged", size: 11, color: .secondaryLabelColor)
    private let displayDetail = DockPanel.label("", size: 11, color: .secondaryLabelColor)
    private let permission = NSButton(title: "Allow Accessibility access…", target: nil, action: nil)
    private let keepOff = NSButton(title: "Keep display off", target: nil, action: nil)
    private let trial = DockPanel.label("Confirm within 15 seconds, or the screen returns.", size: 11, color: .secondaryLabelColor)
    private let recovery = NSButton(title: "Display recovery needs attention…", target: nil, action: nil)
    private let login = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let loginApproval = NSButton(title: "Approve in Login Items…", target: nil, action: nil)

    override func loadView() {
        view = PanelBackground(frame: NSRect(x: 0, y: 0, width: 320, height: 290))
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 320),
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            column.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            column.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])

        let brand = NSStackView(views: [symbol("display", size: 20),
            Self.label("DockMate", size: 16, weight: .semibold), NSView()])
        brand.spacing = 8
        add(brand)
        add(connection)
        column.setCustomSpacing(18, after: connection)

        let controls = NSStackView()
        controls.orientation = .vertical
        controls.spacing = 0
        controls.alignment = .leading
        controls.wantsLayer = true
        controls.layer?.cornerRadius = 10
        controls.addArrangedSubview(row(symbol: "computermouse", title: "Reverse mouse scrolling",
                                        detail: mouseDetail, control: mouseSwitch))
        let line = divider()
        controls.addArrangedSubview(line)
        line.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
        controls.addArrangedSubview(row(symbol: "laptopcomputer", title: "Built-in display",
                                        detail: displayDetail, control: displaySwitch))
        add(controls)

        wire(mouseSwitch, #selector(scrollChanged))
        mouseSwitch.setAccessibilityLabel("Reverse mouse scrolling")
        wire(displaySwitch, #selector(displayChanged))
        displaySwitch.setAccessibilityLabel("Built-in display on")
        for (button, action) in [(permission, #selector(openAccessibility)),
            (recovery, #selector(openRecovery)), (loginApproval, #selector(openLoginSettings))] {
            button.bezelStyle = .inline
            button.font = .systemFont(ofSize: 11)
            button.contentTintColor = .controlAccentColor
            wire(button, action)
            add(button)
        }
        keepOff.bezelStyle = .rounded
        keepOff.controlSize = .regular
        keepOff.keyEquivalent = "\r"
        wire(keepOff, #selector(keepDisplayOff))
        add(keepOff)
        add(trial)

        add(divider())
        login.font = .systemFont(ofSize: 11)
        wire(login, #selector(loginChanged))
        let about = iconButton("info.circle", label: "About DockMate", action: #selector(showAbout))
        let quit = iconButton("power", label: "Quit DockMate", action: #selector(quitApp))
        let footer = NSStackView(views: [login, NSView(), about, quit])
        footer.spacing = 12
        add(footer)
        update(PanelState())
    }

    func update(_ state: PanelState) {
        _ = view
        connection.stringValue = state.externalCount == 0 ? "No external displays connected"
            : "\(state.externalCount) external display\(state.externalCount == 1 ? "" : "s") connected"
        mouseSwitch.state = state.reverseMouse ? .on : .off
        mouseDetail.stringValue = state.reverseMouse && !state.scrollRunning
            ? "Accessibility access needed" : "Trackpad stays unchanged"
        mouseDetail.textColor = state.reverseMouse && !state.scrollRunning ? .systemOrange : .secondaryLabelColor
        permission.isHidden = !state.reverseMouse || state.scrollRunning
        displaySwitch.state = state.builtInOn ? .on : .off
        displaySwitch.isEnabled = state.canChangeDisplay
        if let _ = state.recoveryError {
            displayDetail.stringValue = "Try turning the display back on"
        } else if !state.displayAvailable {
            displayDetail.stringValue = "Unavailable on this Mac"
        } else if !state.builtInOn {
            displayDetail.stringValue = "Off · Touch ID stays available"
        } else if state.externalCount == 0 {
            displayDetail.stringValue = "Connect an external display first"
        } else {
            displayDetail.stringValue = "On · lid can stay open"
        }
        recovery.isHidden = state.recoveryError == nil
        keepOff.isHidden = !state.confirmingDisplay
        trial.isHidden = !state.confirmingDisplay
        login.state = state.launchAtLogin ? .on : .off
        loginApproval.isHidden = !state.loginNeedsApproval
        // System colors resolve again when the popover changes appearance.
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            column.arrangedSubviews.first(where: { $0 is NSStackView && $0.layer?.cornerRadius == 10 })?
                .layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
        view.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(width: 320, height: column.fittingSize.height + 34)
        view.setFrameSize(preferredContentSize)
    }

    private func row(symbol name: String, title: String, detail: NSTextField, control: NSSwitch) -> NSView {
        let text = NSStackView(views: [Self.label(title, size: 12, weight: .medium), detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        let content = NSStackView(views: [symbol(name, size: 18), text, NSView(), control])
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        let row = NSView()
        row.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            content.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 68)
        ])
        // The controls group shares the panel's content width.
        row.widthAnchor.constraint(equalToConstant: 284).isActive = true
        return row
    }

    private func add(_ child: NSView) {
        column.addArrangedSubview(child)
        child.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
    }

    private func divider() -> NSBox {
        let line = NSBox()
        line.boxType = .separator
        return line
    }

    private static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                              color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        return label
    }

    private func symbol(_ name: String, size: CGFloat) -> NSImageView {
        let image = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage())
        image.contentTintColor = .secondaryLabelColor
        image.widthAnchor.constraint(equalToConstant: size).isActive = true
        image.heightAnchor.constraint(equalToConstant: size).isActive = true
        return image
    }

    private func iconButton(_ symbol: String, label: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(),
                              target: self, action: action)
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant: 20).isActive = true
        return button
    }

    private func wire(_ control: NSControl, _ action: Selector) { control.target = self; control.action = action }
    @objc private func scrollChanged() { onScroll?() }
    @objc private func displayChanged() { onDisplay?() }
    @objc private func keepDisplayOff() { onKeepOff?() }
    @objc private func openAccessibility() { onAccessibility?() }
    @objc private func openRecovery() { onRecovery?() }
    @objc private func loginChanged() { onLogin?() }
    @objc private func openLoginSettings() { onLoginSettings?() }
    @objc private func showAbout() { onAbout?() }
    @objc private func quitApp() { onQuit?() }
}

private final class PanelBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}
