import CoreGraphics

/// Tag synthetic events so that the event tap does not process them again.
enum SyntheticInput {
    static let marker: Int64 = 0x4D5041535445 // "MPASTE"

    static func isOurs(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    static func mouse(_ type: CGEventType, at position: CGPoint,
                      button: CGMouseButton = .left, clickCount: Int64 = 1) {
        guard let event = CGEvent(
            mouseEventSource: nil, mouseType: type,
            mouseCursorPosition: position, mouseButton: button
        ) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.setIntegerValueField(.mouseEventClickState, value: clickCount)
        event.post(tap: .cgSessionEventTap)
    }

    static func nativeMiddleClick(at position: CGPoint) {
        mouse(.otherMouseDown, at: position, button: .center)
        mouse(.otherMouseUp, at: position, button: .center)
    }

    static func shortcut(_ key: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { return }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// Unicode keyboard input does NOT touch the macOS clipboard.
    /// Some editors ignore injected Unicode input. This is best-effort.
    @discardableResult
    static func typeUnicode(_ text: String) -> Bool {
        guard !text.isEmpty, text.utf16.count <= 4_000 else { return false }
        let units = Array(text.utf16)
        for start in stride(from: 0, to: units.count, by: 20) {
            let part = Array(units[start..<min(start + 20, units.count)])
            for down in [true, false] {
                guard let event = CGEvent(
                    keyboardEventSource: nil, virtualKey: 0, keyDown: down
                ) else { return false }
                part.withUnsafeBufferPointer { buf in
                    event.keyboardSetUnicodeString(
                        stringLength: buf.count, unicodeString: buf.baseAddress
                    )
                }
                event.setIntegerValueField(.eventSourceUserData, value: marker)
                event.post(tap: .cgSessionEventTap)
            }
        }
        return true
    }
}
