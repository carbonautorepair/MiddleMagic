import AppKit
import ApplicationServices
import CoreGraphics
import MiddlePasteCore

/// Best-effort classification. Never guess that an unknown element is editable.
struct TextHit {
    let kind: HitKind
    let element: AXUIElement?
    let pid: pid_t?
    var secure = false

    static let native = TextHit(kind: .native, element: nil, pid: nil)
}

final class AccessibilityText {
    private let system = AXUIElementCreateSystemWide()

    init() {
        // Prevent an unresponsive target app from indefinitely stalling input.
        AXUIElementSetMessagingTimeout(system, 0.08)
    }

    private var enabledPIDs = Set<pid_t>()
    private let nonTextRoles: Set<String> = [
        "AXScrollBar", "AXSlider", "AXMenuItem", "AXMenuBarItem", "AXCheckBox",
        "AXRadioButton", "AXTabGroup", "AXToolbar", "AXPopUpButton", "AXMenu"
    ]

    /// Chromium/Electron/WebKit apps only expose full web content to
    /// accessibility clients that ask for it.
    private func enableAccessibility(_ pid: pid_t) {
        guard enabledPIDs.insert(pid).inserted else { return }
        let app = AXUIElementCreateApplication(pid)
        let a = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let b = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        Log.write("  enabled AX tree pid=\(pid) manual=\(a.rawValue) enhanced=\(b.rawValue)")
    }

    func hitTest(_ point: CGPoint) -> TextHit {
        Log.write("  app=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
        let h = hitTestInner(point)
        Log.write("  hit kind=\(h.kind) pid=\(h.pid.map(String.init) ?? "-")")
        return h
    }

    private func hitTestInner(_ point: CGPoint) -> TextHit {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            system, Float(point.x), Float(point.y), &element
        )
        guard result == .success, let hit = element else { Log.write("  AX element-at-position failed code=\(result.rawValue)"); return .native }

        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success else { return .native }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard frontPID == pid else { Log.write("  pid mismatch hit=\(pid) front=\(frontPID ?? -1)"); return .native }

        enableAccessibility(pid)
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.meta.endo",
           let field = secureField(at: point, within: hit) {
            var result = TextHit(kind: .editableText, element: field, pid: pid)
            result.secure = true
            return result
        }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome",
           let address = chromeAddress(at: point, within: hit) {
            return TextHit(kind: .editableText, element: address, pid: pid)
        }
        // A hyperlink always wins, even if its accessible descendants are text.
        var node: AXUIElement? = hit
        var editable: AXUIElement?
        var selectable: AXUIElement?
        for _ in 0..<7 {
            guard let current = node else { break }
            AXUIElementSetMessagingTimeout(current, 0.08)
            let role = stringAttribute(kAXRoleAttribute, on: current) ?? ""
            let subrole = stringAttribute(kAXSubroleAttribute, on: current) ?? ""
            Log.write("  node role=\(role) subrole=\(subrole)")
            if role == "AXLink" || nonTextRoles.contains(role) || role.lowercased().contains("button") ||
                subrole.lowercased().contains("secure") || subrole.lowercased().contains("password") {
                return .native
            }
            if ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role) {
                let enabled = boolAttribute(kAXEnabledAttribute, on: current) ?? true
                var settable = DarwinBoolean(false)
                let canEdit = AXUIElementIsAttributeSettable(
                    current, kAXValueAttribute as CFString, &settable
                ) == .success && settable.boolValue
                if enabled && canEdit { editable = current }
                else { selectable = selectable ?? current }
                break
            }
            if role == "AXStaticText" || role == "AXWebArea" {
                selectable = selectable ?? current
            }
            node = parent(of: current)
        }
        if let editable { return TextHit(kind: .editableText, element: editable, pid: pid) }

        // Read-only text (any app) can be captured with a middle-drag.
        // Unknown containers still count: selection is read from the focused
        // element afterwards, and a plain click is replayed unchanged.
        if let selectable { return TextHit(kind: .selectableText, element: selectable, pid: pid) }
        return .native
    }

    // Muse's webview can return an enclosing AXGroup instead of the secure
    // input under the pointer. Inspect geometry and roles, never field values.
    private func secureField(at point: CGPoint, within root: AXUIElement) -> AXUIElement? {
        var queue = [root]
        var examined = 0
        while !queue.isEmpty && examined < 200 {
            let node = queue.removeFirst(); examined += 1
            let role = stringAttribute(kAXRoleAttribute, on: node) ?? ""
            let subrole = (stringAttribute(kAXSubroleAttribute, on: node) ?? "").lowercased()
            if role == "AXTextField", subrole.contains("secure") {
                var p: CFTypeRef?, s: CFTypeRef?
                if AXUIElementCopyAttributeValue(node, kAXPositionAttribute as CFString, &p) == .success,
                   AXUIElementCopyAttributeValue(node, kAXSizeAttribute as CFString, &s) == .success,
                   let p, let s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() {
                    var origin = CGPoint.zero; var size = CGSize.zero
                    if AXValueGetValue(p as! AXValue, .cgPoint, &origin),
                       AXValueGetValue(s as! AXValue, .cgSize, &size),
                       CGRect(origin: origin, size: size).contains(point) { return node }
                }
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &children) == .success,
               let nodes = children as? [AXUIElement] { queue.append(contentsOf: nodes.prefix(100)) }
        }
        return nil
    }

    private func chromeAddress(at point: CGPoint, within hit: AXUIElement) -> AXUIElement? {
        var queue = [hit]
        var examined = 0
        while !queue.isEmpty && examined < 150 {
            let node = queue.removeFirst()
            examined += 1
            let role = stringAttribute(kAXRoleAttribute, on: node) ?? ""
            if role == "AXTextField",
               stringAttribute(kAXDescriptionAttribute, on: node) == "Address and search bar" {
                var p: CFTypeRef?, s: CFTypeRef?
                if AXUIElementCopyAttributeValue(node, kAXPositionAttribute as CFString, &p) == .success,
                   AXUIElementCopyAttributeValue(node, kAXSizeAttribute as CFString, &s) == .success,
                   let p, let s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() {
                    var origin = CGPoint.zero; var size = CGSize.zero
                    if AXValueGetValue(p as! AXValue, .cgPoint, &origin),
                       AXValueGetValue(s as! AXValue, .cgSize, &size),
                       CGRect(origin: origin, size: size).contains(point) { return node }
                }
            }
            if role == "AXWebArea" { continue }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &children) == .success,
               let nodes = children as? [AXUIElement] { queue.append(contentsOf: nodes.prefix(100)) }
        }
        return nil
    }

    func selectedText(near hit: TextHit) -> String? {
        // Never capture a selection from a different app after a focus change.
        guard let expectedPID = hit.pid,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID
        else { return nil }
        // Browser DOM text selection often belongs to the AXWebArea rather
        // than the smallest element under the mouse.
        var candidates: [AXUIElement] = []
        if let focused = focusedElement() {
            var focusedPID: pid_t = 0
            if AXUIElementGetPid(focused, &focusedPID) == .success,
               focusedPID == expectedPID { candidates.append(focused) }
        }
        if let element = hit.element {
            candidates.append(element)
            var current: AXUIElement? = element
            for _ in 0..<7 {
                guard let p = current.flatMap({ parent(of: $0) }) else { break }
                candidates.append(p)
                current = p
            }
        }
        for candidate in candidates {
            guard let text = stringAttribute(kAXSelectedTextAttribute, on: candidate),
                  !text.isEmpty else { continue }
            return text
        }
        return nil
    }

    func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &value
        ) == .success else { return nil }
        guard let value else { return nil }
        // Using the CF type identifier avoids an unsafe Swift cast.
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func isFocused(_ element: AXUIElement) -> Bool {
        guard let focused = focusedElement() else { return false }
        return CFEqual(element, focused)
    }

    /// Preserve a destination's actual text selection for replacement.
    /// If no selected range can be identified, a middle-click should place
    /// the caret at the pointer instead of pasting at some old caret position.
    func hasNonemptySelection(_ element: AXUIElement) -> Bool {
        if let selected = stringAttribute(kAXSelectedTextAttribute, on: element),
           !selected.isEmpty { return true }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &raw
        ) == .success, let raw, CFGetTypeID(raw) == AXValueGetTypeID()
        else { return false }
        let rangeValue = raw as! AXValue
        guard AXValueGetType(rangeValue) == .cfRange else { return false }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue, .cfRange, &range) else { return false }
        return range.length > 0
    }

    func focusedEditableElement(for pid: pid_t?) -> AXUIElement? {
        guard let focused = focusedElement() else { return nil }
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focused, &focusedPID) == .success,
              focusedPID == pid else { return nil }
        let role = stringAttribute(kAXRoleAttribute, on: focused) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute, on: focused) ?? ""
        guard !subrole.lowercased().contains("secure"),
              !subrole.lowercased().contains("password"),
              ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role)
        else { return nil }
        return focused
    }

    /// Some native controls implement writable AXSelectedText, but some web
    /// editors ignore it even when they report success. No clipboard changes.
    func replaceSelectedText(_ text: String, in element: AXUIElement) -> Bool {
        var writable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element, kAXSelectedTextAttribute as CFString, &writable
        ) == .success, writable.boolValue else { return false }
        return AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        ) == .success
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXParentAttribute as CFString, &value
        ) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ name: String, on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, name as CFString, &value
        ) == .success else { return nil }
        return value as? String
    }

    private func boolAttribute(_ name: String, on element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, name as CFString, &value
        ) == .success else { return nil }
        return value as? Bool
    }
}
