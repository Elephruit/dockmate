import AppKit
import ApplicationServices
import DockMateCore

final class ScrollController {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private(set) var enabled = false
    var onChange: (() -> Void)?
    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    @discardableResult
    func start(prompt: Bool) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            guard AXIsProcessTrustedWithOptions(options) else { return false }
        } else if !AXIsProcessTrusted() { return false }
        if let tap {
            enabled = true
            CGEvent.tapEnable(tap: tap, enable: true)
            return isRunning
        }
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: scrollCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) else {
            CFMachPortInvalidate(created)
            return false
        }
        tap = created
        source = runLoopSource
        enabled = true
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        return true
    }

    func stop() {
        enabled = false
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if enabled, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            DispatchQueue.main.async { [weak self] in self?.onChange?() }
        } else if enabled && ScrollPolicy.shouldReverse(event) {
            ScrollPolicy.reverse(event)
        }
        return Unmanaged.passUnretained(event)
    }
}

private let scrollCallback: CGEventTapCallBack = { _, type, event, context in
    guard let context else { return Unmanaged.passUnretained(event) }
    return Unmanaged<ScrollController>.fromOpaque(context).takeUnretainedValue().handle(type, event)
}
