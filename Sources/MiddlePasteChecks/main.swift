import Foundation
import MiddlePasteCore

var failures = 0
var total = 0
func check(_ cond: Bool, _ name: String) {
    total += 1
    if cond { print("PASS \(name)") } else { failures += 1; print("FAIL \(name)") }
}

// emptySelectionNeverOverwrites
do {
    let bank = MiddleBuffer()
    check(bank.capture("Source text"), "capture accepts text")
    check(!bank.capture(""), "empty capture rejected")
    check(!bank.capture(nil), "nil capture rejected")
    check(bank.text == "Source text", "buffer kept after empty capture")
}
// captureDoesNotDependOnSystemClipboard
do {
    let bank = MiddleBuffer()
    check(bank.capture("hello"), "capture hello")
    check(bank.text == "hello", "text is hello")
    bank.clear()
    check(bank.isEmpty, "clear empties buffer")
}
// nativeTargetsAreNotIntercepted
check(!GestureRouter.shouldIntercept(.native), "native not intercepted")
check(GestureRouter.shouldIntercept(.editableText), "editable intercepted")
check(GestureRouter.shouldIntercept(.selectableText), "selectable intercepted")
// routing
check(GestureRouter.decide(hit: .editableText, dragged: false, hasBuffer: true) == .paste, "editable+buffer -> paste")
check(GestureRouter.decide(hit: .editableText, dragged: false, hasBuffer: false) == .replayNativeClick, "editable+empty -> replay")
check(GestureRouter.decide(hit: .selectableText, dragged: false, hasBuffer: true) == .replayNativeClick, "selectable click -> replay")
check(GestureRouter.decide(hit: .selectableText, dragged: true, hasBuffer: true) == .captureSelection, "selectable drag -> capture")

print("\(total - failures)/\(total) checks passed")
exit(failures == 0 ? 0 : 1)
