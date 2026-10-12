import AppKit
import CoreGraphics
import DockMateCore
import Darwin

final class DisplayController {
    private typealias Configure = @convention(c) (CGDisplayConfigRef, UInt32, Bool) -> Int32
    private typealias List = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> Int32
    private let library: UnsafeMutableRawPointer?
    private let configure: Configure?
    private let list: List?
    private let defaults = UserDefaults.standard
    private var watchdog: Timer?
    private var preview: Timer?
    private var observers: [NSObjectProtocol] = []
    var onChange: (() -> Void)?
    private(set) var lastError: String?
    private(set) var awaitingConfirmation = false
    private(set) var disabledByApp: Bool

    init() {
        disabledByApp = defaults.bool(forKey: "displayRestorePending")
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        library = handle
        configure = handle.flatMap { dlsym($0, "SLSConfigureDisplayEnabled") }
            .map { unsafeBitCast($0, to: Configure.self) }
        list = handle.flatMap { dlsym($0, "SLSGetDisplayList") }
            .map { unsafeBitCast($0, to: List.self) }
    }

    var isSupported: Bool { configure != nil && list != nil }
    var activeDisplays: [CGDirectDisplayID] {
        var ids = [UInt32](repeating: 0, count: 64)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(64, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
    var externalCount: Int { activeDisplays.filter { CGDisplayIsBuiltin($0) == 0 }.count }
    var builtInActive: Bool { activeDisplays.contains { CGDisplayIsBuiltin($0) != 0 } }
    var builtInID: CGDirectDisplayID? {
        var ids = [UInt32](repeating: 0, count: 64)
        var count: UInt32 = 0
        if let list, list(64, &ids, &count) == 0,
           let id = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            return id
        }
        return activeDisplays.first { CGDisplayIsBuiltin($0) != 0 }
    }

    func start() {
        CGDisplayRegisterReconfigurationCallback(displayChanged, Unmanaged.passUnretained(self).toOpaque())
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.restoreIfNeeded()
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            self?.restoreIfNeeded()
            self?.onChange?()
        })
        // A previous abnormal exit may have left the panel disabled.
        if disabledByApp {
            restoreIfNeeded()
            if disabledByApp { startWatchdog() }
        }
    }

    func turnOff() throws {
        guard DisplayPolicy.canTurnOff(hasBuiltIn: builtInActive, activeExternalCount: externalCount) else {
            throw Failure("Connect an active external monitor before turning off the built-in display.")
        }
        // Persist recovery intent before changing hardware, including a partially failed transaction.
        disabledByApp = true
        defaults.set(true, forKey: "displayRestorePending")
        defaults.synchronize()
        startWatchdog()
        do { try setEnabled(false) } catch {
            restoreIfNeeded()
            throw error
        }
        awaitingConfirmation = true
        preview?.invalidate()
        preview = Timer(timeInterval: 15, repeats: false) { [weak self] _ in self?.restoreIfNeeded() }
        RunLoop.main.add(preview!, forMode: .common)
        onChange?()
    }

    func keepOff() {
        preview?.invalidate()
        preview = nil
        awaitingConfirmation = false
        onChange?()
    }

    func restore() throws {
        try setEnabled(true)
        disabledByApp = false
        defaults.set(false, forKey: "displayRestorePending")
        lastError = nil
        watchdog?.invalidate()
        watchdog = nil
        keepOff()
    }

    func restoreIfNeeded() {
        guard disabledByApp else { return }
        do { try restore() } catch {
            lastError = "Could not restore display: \(error.localizedDescription)"
            onChange?()
        }
    }

    func topologyChanged() {
        if disabledByApp && builtInActive {
            // macOS may have restored it itself after a topology change.
            disabledByApp = false
            defaults.set(false, forKey: "displayRestorePending")
            watchdog?.invalidate()
            watchdog = nil
            keepOff()
        } else if DisplayPolicy.shouldRestore(disabledByApp: disabledByApp, activeExternalCount: externalCount) {
            restoreIfNeeded()
        }
        onChange?()
    }

    func stop() throws {
        if disabledByApp { try restore() }
        CGDisplayRemoveReconfigurationCallback(displayChanged, Unmanaged.passUnretained(self).toOpaque())
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        // Runs only while the panel is off, also catching missed hot-plug notifications.
        watchdog = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.lastError != nil { self.restoreIfNeeded() }
            self.topologyChanged()
        }
        RunLoop.main.add(watchdog!, forMode: .common)
    }

    private func setEnabled(_ enabled: Bool) throws {
        guard let configure, let id = builtInID else {
            throw Failure("Built-in display control is unavailable on this Mac or macOS version.")
        }
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else { throw Failure("Cannot begin display configuration (\(begin.rawValue)).") }
        let result = configure(config, id, enabled)
        guard result == 0 else {
            CGCancelDisplayConfiguration(config)
            throw Failure("macOS rejected the display change (\(result)).")
        }
        // Session-only: do not write a permanent system display configuration.
        let commit = CGCompleteDisplayConfiguration(config, .forSession)
        guard commit == .success else { throw Failure("Cannot apply display configuration (\(commit.rawValue)).") }
        lastError = nil
    }
}

private let displayChanged: CGDisplayReconfigurationCallBack = { _, flags, context in
    guard !flags.contains(.beginConfigurationFlag), let context else { return }
    let controller = Unmanaged<DisplayController>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { controller.topologyChanged() }
}

struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
