import Testing
@testable import MiddlePasteCore

@Suite struct MiddleBufferTests {
    @Test func emptySelectionNeverOverwrites() {
        let bank = MiddleBuffer()
        #expect(bank.capture("Source text"))
        #expect(!bank.capture(""))
        #expect(!bank.capture(nil))
        #expect(bank.text == "Source text")
    }

    @Test func captureDoesNotDependOnSystemClipboard() {
        let bank = MiddleBuffer()
        #expect(bank.capture("hello"))
        #expect(bank.text == "hello")
        bank.clear()
        #expect(bank.isEmpty)
    }

    @Test func nativeTargetsAreNotIntercepted() {
        #expect(!GestureRouter.shouldIntercept(.native))
        #expect(GestureRouter.shouldIntercept(.editableText))
        #expect(GestureRouter.shouldIntercept(.selectableText))
    }

    @Test func routing() {
        #expect(GestureRouter.decide(hit: .editableText, dragged: false, hasBuffer: true) == .paste)
        #expect(GestureRouter.decide(hit: .editableText, dragged: false, hasBuffer: false) == .replayNativeClick)
        #expect(GestureRouter.decide(hit: .selectableText, dragged: false, hasBuffer: true) == .replayNativeClick)
        #expect(GestureRouter.decide(hit: .selectableText, dragged: true, hasBuffer: true) == .captureSelection)
    }
}
