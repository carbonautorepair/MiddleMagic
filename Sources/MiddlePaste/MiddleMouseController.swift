import AppKit
import ApplicationServices
import CoreGraphics
import MiddlePasteCore

final class MiddleMouseController {
    let bank: MiddleBuffer
    let accessibility = AccessibilityText()
    var onChange: (() -> Void)?
    var enabled = true

    private var tap: CFMachPort?
    var isActive: Bool { tap != nil }
    private var source: CFRunLoopSource?
    private var leftStart: CGPoint?
    private var swallowMiddleUp = false
    private let dragThreshold: CGFloat = 4

    init(bank: MiddleBuffer) { self.bank = bank }

    @discardableResult
    func start() -> Bool {
        guard AXIsProcessTrusted() else { Log.write("start: Accessibility NOT trusted"); return false }
        if tap != nil { return true }
        let types: [CGEventType] = [
            .otherMouseDown, .otherMouseUp, .leftMouseDown, .leftMouseUp
        ]
        let mask = types.reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: middleEventCallback,
            userInfo: userInfo
        ) else { Log.write("start: tapCreate failed"); return false }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault, port, 0
        ) else { return false }
        tap = port
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        Log.write("start: listener active")
        return true
    }

    func stop() {
        if let port = tap { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes) }
        tap = nil
        source = nil
        leftStart = nil
    }

    /// Returns true to forward this real event, false to suppress it.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if SyntheticInput.isOurs(event) { return true }
        if !enabled { return true }
        switch type {
        case .leftMouseDown:
            leftStart = event.location
            return true
        case .leftMouseUp:
            let clicks = event.getIntegerValueField(.mouseEventClickState)
            let end = event.location
            if let start = leftStart {
                let moved = hypot(end.x - start.x, end.y - start.y) >= dragThreshold
                if moved || clicks >= 2 { copyLeftSelection(at: end) }
            }
            leftStart = nil
            return true
        case .otherMouseDown:
            guard event.getIntegerValueField(.mouseEventButtonNumber) == 2 else { return true }
            let hit = accessibility.hitTest(event.location)
            guard hit.kind == .editableText else { return true }
            swallowMiddleUp = true
            let point = event.location
            let pid = hit.pid
            SyntheticInput.mouse(.leftMouseDown, at: point)
            SyntheticInput.mouse(.leftMouseUp, at: point)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                SyntheticInput.shortcut(9, flags: .maskControl) // Control-V
            }
            return false
        case .otherMouseUp:
            guard event.getIntegerValueField(.mouseEventButtonNumber) == 2, swallowMiddleUp else { return true }
            swallowMiddleUp = false
            return false
        default: return true
        }
    }

    private func copyLeftSelection(at point: CGPoint) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            let hit = self.accessibility.hitTest(point)
            guard hit.kind != .native, !hit.secure,
                  self.accessibility.selectedText(near: hit) != nil else { return }
            SyntheticInput.shortcut(8, flags: .maskCommand) // Command-C
        }
    }

    fileprivate func recoverTap() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

private let middleEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let mouse = Unmanaged<MiddleMouseController>
        .fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DispatchQueue.main.async { mouse.recoverTap() }
        return Unmanaged.passUnretained(event)
    }
    return mouse.handle(type: type, event: event)
        ? Unmanaged.passUnretained(event) : nil
}
