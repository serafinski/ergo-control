import XCTest
import ErgoCore
@testable import ErgoControl

/// Exercise the real engine with an output sink; never post input to the Mac.
final class ActionEngineTests: XCTestCase {
    func testLettersAndReturnDiscardInheritedFnKeypadAndUnheldModifiers() throws {
        for usage: UInt8 in [7,8,40,42,44,224,226] {
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState),
                virtualKey: MacKeys.codes[usage]!, keyDown: true))
            // Reproduce a source contaminated by preceding navigation events.
            event.flags = [.maskSecondaryFn,.maskNumericPad,.maskCommand,.maskShift]
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
            MacKeys.configure(event, usage: usage, repeated: false, modifiers: 0, capsLock: false)
            XCTAssertEqual(event.flags, [], "Unexpected flags on HID usage \(usage)")
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventAutorepeat), 0)
            MacKeys.configure(event, usage: usage, repeated: false, modifiers: 5, capsLock: false)
            XCTAssertTrue(event.flags.contains([.maskControl,.maskAlternate]))
            XCTAssertFalse(event.flags.contains(.maskSecondaryFn))
            XCTAssertFalse(event.flags.contains(.maskNumericPad))
            XCTAssertFalse(event.flags.contains(.maskCommand))
        }
    }

    func testControlOptionReturnRemainsDistinctFromKeypadEnter() throws {
        let source = CGEventSource(stateID: .privateState)
        for pressed in [true,false] {
            _ = MacKeys.event(usage: 80, pressed: pressed, repeated: false,
                              modifiers: 5, capsLock: false, source: source)
            let main = try XCTUnwrap(MacKeys.event(usage: 40, pressed: pressed, repeated: false,
                modifiers: 5, capsLock: false, source: source))
            XCTAssertEqual(main.getIntegerValueField(.keyboardEventKeycode), 36)
            XCTAssertEqual(main.flags, MacKeys.flags(5))
            let keypad = try XCTUnwrap(MacKeys.event(usage: 88, pressed: pressed, repeated: false,
                modifiers: 5, capsLock: false, source: source))
            XCTAssertEqual(keypad.getIntegerValueField(.keyboardEventKeycode), 76)
            XCTAssertEqual(keypad.flags, MacKeys.flags(5).union(.maskNumericPad))
            XCTAssertFalse(keypad.flags.contains(.maskSecondaryFn))
        }
    }

    func testArrowEventsKeepNativeMetadataAndBothModifierSides() throws {
        for usage: UInt8 in 79...82 {
            for mods: UInt8 in [0x05,0x50] {
                let event = try XCTUnwrap(MacKeys.event(usage: usage, pressed: true, repeated: false,
                    modifiers: mods, capsLock: false, source: CGEventSource(stateID: .privateState)))
                XCTAssertEqual(event.type, .keyDown)
                XCTAssertTrue(event.flags.contains([.maskControl,.maskAlternate,.maskNumericPad,.maskSecondaryFn]))
                XCTAssertEqual(event.flags.rawValue & 0x2061, mods == 5 ? 0x21 : 0x2040)
                XCTAssertFalse(event.flags.contains(.maskCommand))
                XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), Int64(MacKeys.codes[usage]!))
            }
        }
    }
    func testBackspaceUsesProvidedRepeatTimingAndStopsOnRelease() {
        var output: [(KeyboardOutput, Bool)] = []
        let engine = ActionEngine(repeatTiming: { NativeKeyboardTiming(delay: 0.4, interval: 0.4) },
                                  keyOutput: { output.append(($0,$1)) })
        engine.relay(42, pressed: true, owner: "extra:251")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(output.count, 1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        XCTAssertEqual(output.filter(\.1).count, 1)
        engine.relay(42, pressed: false, owner: "extra:251")
        XCTAssertEqual(output.last?.0, KeyboardOutput(42, pressed: false, modifiers: 0))
        let count = output.count
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(output.count, count)
        engine.stop()
    }
    func testRepeatedPlayPauseWithoutNeutralReportsProducesBalancedEvents() {
        var output: [ConsumerKeyEvent] = []
        let engine = ActionEngine(mediaOutput: { usage, pressed in output.append(ConsumerKeyEvent(usage, pressed: pressed)) })
        var state = ConsumerKeyState()
        let press = Data([3,0xcd] + Array(repeating: 0, count: 10))
        for time in [0.0, 1, 2] {
            for event in state.decode(press, at: time)! { XCTAssertTrue(engine.media(event.usage, pressed: event.pressed)) }
            for event in state.releaseExpired(at: time + 0.31) { XCTAssertTrue(engine.media(event.usage, pressed: event.pressed)) }
        }
        XCTAssertEqual(output, (0..<3).flatMap { _ in [ConsumerKeyEvent(0xcd, pressed: true), ConsumerKeyEvent(0xcd, pressed: false)] })
        engine.stop()
        XCTAssertEqual(output.count, 6)
    }
    func testStopReleasesHeldMediaAndRejectsUnknownOutput() {
        var output: [ConsumerKeyEvent] = []
        let engine = ActionEngine(mediaOutput: { usage, pressed in output.append(ConsumerKeyEvent(usage, pressed: pressed)) })
        XCTAssertFalse(engine.media(0xffff, pressed: true))
        XCTAssertTrue(engine.media(0xcd, pressed: true))
        engine.stop()
        XCTAssertEqual(output, [ConsumerKeyEvent(0xcd, pressed: true), ConsumerKeyEvent(0xcd, pressed: false)])
    }
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
