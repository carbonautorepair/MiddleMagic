import Foundation

/// Completely separate from NSPasteboard.general and other clipboard history tools.
/// Deliberately ephemeral: data is cleared when the app exits.
public final class MiddleBuffer {
    public private(set) var text: String?

    public init() {}

    /// An empty/failed selection must NOT erase an earlier useful capture.
    @discardableResult
    public func capture(_ selectedText: String?) -> Bool {
        guard let selectedText, !selectedText.isEmpty else { return false }
        text = selectedText
        return true
    }

    public func clear() { text = nil }
    public var isEmpty: Bool { text == nil }
    public var characterCount: Int { text?.count ?? 0 }
}

public enum HitKind: Equatable {
    case editableText
    case selectableText
    case native
}

public enum GestureDecision: Equatable {
    case paste
    case captureSelection
    case replayNativeClick
}

/// Pure, testable rules. Non-text targets aren't intercepted at all.
public enum GestureRouter {
    public static func shouldIntercept(_ hit: HitKind) -> Bool {
        hit == .editableText || hit == .selectableText
    }

    public static func decide(hit: HitKind, dragged: Bool, hasBuffer: Bool) -> GestureDecision {
        if dragged { return .captureSelection }
        if hit == .editableText && hasBuffer { return .paste }
        return .replayNativeClick
    }
}
