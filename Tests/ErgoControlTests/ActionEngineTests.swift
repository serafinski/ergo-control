import XCTest
import ErgoCore
@testable import ErgoControl

/// Exercise the real engine with an output sink; never post input to the Mac.
final class ActionEngineTests: XCTestCase {
    func testKeyboardBrightnessUsesDeviceCallbackInsteadOfMacKeyEvents() {
        var output: [KeyboardOutput] = []
        var turns: [Int] = []
        var error: String?
        let engine = ActionEngine { event, _ in output.append(event) }
        engine.onBrightness = { turns.append($0) }
        engine.onError = { error = $0 }
        engine.perform(MappingAction(.keyboardBrightness, "up"), fromDial: true)
        engine.perform(MappingAction(.keyboardBrightness, "down"), fromDial: true)
        engine.perform(MappingAction(.keyboardBrightness, "invalid"))
        XCTAssertEqual(turns, [1, -1]); XCTAssertTrue(output.isEmpty)
        XCTAssertNotNil(error)
        engine.stop()
    }
    func testDialSwitcherRenewsIdleTimerThenReleasesCommand() {
        var output: [KeyboardOutput] = []
        let engine = ActionEngine { event, _ in output.append(event) }
        engine.perform(MappingAction(.shortcut, "cmd+tab"), fromDial: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        engine.perform(MappingAction(.shortcut, "cmd+shift+tab"), fromDial: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertEqual(output.count, 5)
        XCTAssertEqual(output.last, KeyboardOutput(43, pressed: false, modifiers: 8))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(output.last, KeyboardOutput(227, pressed: false, modifiers: 0))
        engine.stop()
        XCTAssertEqual(output.count, 6)
    }

    func testOrdinaryTypingEndsSwitcherBeforeForwardingKey() {
        var output: [KeyboardOutput] = []
        let engine = ActionEngine { event, _ in output.append(event) }
        engine.perform(MappingAction(.shortcut, "cmd+tab"), fromDial: true)
        engine.relay(44, pressed: true, owner: "extra:253")
        XCTAssertEqual(Array(output.suffix(2)), [
            KeyboardOutput(227, pressed: false, modifiers: 0),
            KeyboardOutput(44, pressed: true, modifiers: 0)])
        engine.stop()
        XCTAssertEqual(output.last, KeyboardOutput(44, pressed: false, modifiers: 0))
    }

    func testButtonShortcutIsStillOneShotAndStopReleasesDialCommand() {
        var output: [KeyboardOutput] = []
        let engine = ActionEngine { event, _ in output.append(event) }
        engine.perform(MappingAction(.shortcut, "cmd+tab"))
        XCTAssertEqual(output, [KeyboardOutput(43, pressed: true, modifiers: 8), KeyboardOutput(43, pressed: false, modifiers: 0)])
        engine.perform(MappingAction(.shortcut, "cmd+tab"), fromDial: true)
        engine.stop()
        XCTAssertEqual(output.last, KeyboardOutput(227, pressed: false, modifiers: 0))
        let count = output.count
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        XCTAssertEqual(output.count, count)
    }

    func testSplitSpaceRepeatsAndFirstHalfReleaseDoesNotStopIt() {
        var output: [(KeyboardOutput, Bool)] = []
        let engine = ActionEngine { event, repeatEvent in output.append((event, repeatEvent)) }
        engine.physicalModifiers = 2
        engine.relay(44, pressed: true)
        engine.relay(44, pressed: true, owner: "extra:253")
        engine.relay(44, pressed: false)
        XCTAssertEqual(output.count, 1)
        RunLoop.main.run(until: Date().addingTimeInterval(2.1))
        XCTAssertTrue(output.contains(where: { $0.1 && $0.0 == KeyboardOutput(44, pressed: true, modifiers: 2) }))
        engine.relay(44, pressed: false, owner: "extra:253")
        XCTAssertEqual(output.last?.0, KeyboardOutput(44, pressed: false, modifiers: 2))
        let count = output.count
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(output.count, count)
        engine.stop()
    }
}
