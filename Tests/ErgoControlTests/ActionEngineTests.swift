import XCTest
import AppKit
import ErgoCore
@testable import ErgoControl

/// Exercise the real engine with an output sink; never post input to the Mac.
final class ActionEngineTests: XCTestCase {
    func testRequestedFunctionActionsFireOncePerPressAndCustomShortcutsBypassThem() {
        var actions: [NativeFunctionAction] = []
        var keys: [KeyboardOutput] = []
        let engine = ActionEngine(functionActionOutput: { actions.append($0) },
                                  repeatTiming: { NativeKeyboardTiming(delay: 0.05, interval: 0.05) },
                                  keyOutput: { keys.append($0); _ = $1 })
        let requests: [(UInt8, NativeFunctionAction)] = [(60,.missionControl),(61,.spotlight),(62,.dictation),(63,.emoji),(67,.lockScreen)]
        for (usage, action) in requests {
            let before = actions.count
            engine.relay(usage, pressed: true)
            engine.relay(usage, pressed: true) // Duplicate snapshot while held.
            RunLoop.main.run(until: Date().addingTimeInterval(0.13))
            engine.relay(usage, pressed: false)
            XCTAssertEqual(Array(actions.dropFirst(before)), [action])
        }
        XCTAssertTrue(keys.isEmpty)
        for usage: UInt8 in 64...66 { engine.relay(usage, pressed: true); engine.relay(usage, pressed: false) }
        XCTAssertEqual(keys.map(\.usage), [64,64,65,65,66,66], "F7–F9 keep their existing raw-key behavior")
        let count = actions.count
        for f in [3,4,5,6,10,11,12] { engine.perform(MappingAction(.shortcut, "f\(f)")) }
        XCTAssertEqual(actions.count, count, "Explicit shortcut mappings must remain raw F-keys")
        engine.stop()
        XCTAssertEqual(actions.count, count, "Stopping cannot re-trigger a system action")
    }

    func testFunctionProvidersRouteChoicesWithoutChangingExplicitShortcuts() {
        var actions: [NativeFunctionAction] = []
        var keys: [KeyboardOutput] = []
        let engine = ActionEngine(functionActionOutput: { actions.append($0) }, keyOutput: { keys.append($0); _ = $1 })
        engine.functionKeys = FunctionKeyPreferences(search: .raycast, dictation: .fluidVoice)
        for usage: UInt8 in [61,62] { engine.relay(usage, pressed: true); engine.relay(usage, pressed: false) }
        XCTAssertEqual(actions, [.raycast,.fluidVoice])
        engine.functionKeys = FunctionKeyPreferences()
        for usage: UInt8 in [61,62] { engine.relay(usage, pressed: true); engine.relay(usage, pressed: false) }
        XCTAssertEqual(actions, [.raycast,.fluidVoice,.spotlight,.dictation])
        engine.perform(MappingAction(.shortcut, "f4")); engine.perform(MappingAction(.shortcut, "f5"))
        XCTAssertEqual(actions.count, 4)
        XCTAssertEqual(keys.map(\.usage), [61,61,62,62])
        engine.stop()
    }

    func testFluidVoiceFollowsPhysicalF5LifetimeAndReleasesAfterPreferenceChangeOrStop() {
        var keys: [KeyboardOutput] = []
        let engine = ActionEngine(fluidVoiceAvailable: { true },
                                  repeatTiming: { NativeKeyboardTiming(delay: 0.05, interval: 0.05) },
                                  keyOutput: { keys.append($0); _ = $1 })
        engine.functionKeys.dictation = .fluidVoice
        engine.relay(62, pressed: true); engine.relay(62, pressed: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.13))
        XCTAssertEqual(keys, [KeyboardOutput(230, pressed: true, modifiers: 64)])
        engine.functionKeys.dictation = .apple
        engine.functionKeys.fluidVoiceShortcut = "ctrl+shift+space"
        engine.relay(62, pressed: false)
        XCTAssertEqual(keys.last, KeyboardOutput(230, pressed: false, modifiers: 0))
        engine.relay(7, pressed: true); engine.relay(7, pressed: false)
        XCTAssertEqual(keys.last, KeyboardOutput(7, pressed: false, modifiers: 0))
        engine.functionKeys.dictation = .fluidVoice
        engine.functionKeys.fluidVoiceShortcut = "rightoption"
        engine.relay(62, pressed: true); engine.stop()
        XCTAssertEqual(keys.suffix(2), [KeyboardOutput(230, pressed: true, modifiers: 64), KeyboardOutput(230, pressed: false, modifiers: 0)])
        let count = keys.count
        engine.relay(62, pressed: false)
        XCTAssertEqual(keys.count, count)
    }

    func testFluidVoiceChordReleasesOnlyItsOwnModifiersAndRetainsThemDuringOtherInput() {
        var keys: [KeyboardOutput] = []
        let engine = ActionEngine(fluidVoiceAvailable: { true }, keyOutput: { keys.append($0); _ = $1 })
        engine.functionKeys = FunctionKeyPreferences(dictation: .fluidVoice, fluidVoiceShortcut: "ctrl+shift+space")
        engine.physicalModifiers = 1
        engine.relay(62, pressed: true)
        XCTAssertEqual(keys, [KeyboardOutput(225, pressed: true, modifiers: 3), KeyboardOutput(44, pressed: true, modifiers: 3)])
        engine.relay(4, pressed: true); engine.relay(4, pressed: false)
        XCTAssertEqual(keys.last, KeyboardOutput(4, pressed: false, modifiers: 3))
        engine.relay(62, pressed: false)
        XCTAssertEqual(keys.suffix(2), [KeyboardOutput(44, pressed: false, modifiers: 3), KeyboardOutput(225, pressed: false, modifiers: 1)])
        XCTAssertFalse(keys.contains { $0.usage == 224 }, "Do not release the user's held Control key")
        engine.functionKeys.fluidVoiceShortcut = "rightoption"
        engine.physicalModifiers = 0; engine.relay(62, pressed: true)
        engine.physicalModifiers = 64; engine.relay(230, pressed: true)
        let count = keys.count
        engine.relay(62, pressed: false)
        XCTAssertEqual(keys.count, count, "A real Option press takes ownership before F5 is released")
        engine.physicalModifiers = 0; engine.relay(230, pressed: false)
        XCTAssertEqual(keys.last, KeyboardOutput(230, pressed: false, modifiers: 0))
        let before = keys.count
        engine.relay(62, pressed: true)
        engine.physicalModifiers = 64; engine.relay(230, pressed: true)
        engine.physicalModifiers = 0; engine.relay(230, pressed: false)
        XCTAssertEqual(keys.count, before + 1, "Physical Option cannot release the still-held F5 trigger")
        engine.relay(62, pressed: false)
        XCTAssertEqual(keys.suffix(2), [KeyboardOutput(230, pressed: true, modifiers: 64), KeyboardOutput(230, pressed: false, modifiers: 0)])
        engine.relay(62, pressed: true)
        engine.physicalModifiers = 64; engine.relay(230, pressed: true)
        engine.stop()
        XCTAssertEqual(keys.last, KeyboardOutput(230, pressed: false, modifiers: 0), "Stop must release a shared modifier even when its first press came from Fluid Voice")
    }

    func testUnavailableFluidVoiceAndInvalidShortcutLeaveOrdinaryInputWorking() {
        for available in [false,true] {
            var keys: [KeyboardOutput] = [], notices: [String] = [], errors: [String] = []
            let engine = ActionEngine(fluidVoiceAvailable: { available }, keyOutput: { keys.append($0); _ = $1 })
            engine.functionKeys = FunctionKeyPreferences(dictation: .fluidVoice, fluidVoiceShortcut: available ? "d" : "rightoption")
            engine.onNotice = { notices.append($0) }; engine.onError = { errors.append($0) }
            engine.relay(62, pressed: true); engine.relay(62, pressed: false)
            XCTAssertEqual(notices.count, 1); XCTAssertTrue(keys.isEmpty); XCTAssertTrue(errors.isEmpty)
            engine.relay(4, pressed: true); engine.relay(4, pressed: false)
            XCTAssertEqual(keys.map(\.usage), [4,4])
            engine.stop()
        }
    }

    func testF11F12UseKeyboardBacklightCallbackInRequestedDirectionsAndStopOnRelease() {
        var steps: [Int] = []
        var keys: [KeyboardOutput] = []
        let engine = ActionEngine(repeatTiming: { NativeKeyboardTiming(delay: 0.1, interval: 0.2) },
                                  keyOutput: { keys.append($0); _ = $1 })
        engine.onBrightness = { steps.append($0) }
        engine.relay(68, pressed: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        engine.relay(68, pressed: false)
        XCTAssertEqual(steps, [-1,-1], "F11 lowers the Ergo backlight, including when held")
        engine.relay(69, pressed: true); engine.relay(69, pressed: false)
        XCTAssertEqual(steps, [-1,-1,1], "F12 raises the Ergo backlight")
        let count = steps.count
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        XCTAssertEqual(steps.count, count)
        XCTAssertTrue(keys.isEmpty)
        engine.stop()
    }

    func testDictationShortcutBalancesFnAndFollowingLettersStayOrdinary() throws {
        let source = CGEventSource(stateID: .privateState)
        let events = try XCTUnwrap(MacKeys.dictationEvents(modifiers: 0, capsLock: false, source: source))
        XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [63,2,2,63])
        XCTAssertEqual(events.map(\.type), [.flagsChanged,.keyDown,.keyUp,.flagsChanged])
        XCTAssertTrue(events.prefix(3).allSatisfy { $0.flags == .maskSecondaryFn })
        XCTAssertEqual(events.last?.flags, [])
        for usage: UInt8 in [7,8,40] {
            let event = try XCTUnwrap(MacKeys.event(usage: usage, pressed: true, repeated: false,
                                                   modifiers: 0, capsLock: false, source: source))
            XCTAssertEqual(event.flags, [], "Fn must never leak into D/E/Return after dictation")
        }
    }

    func testDefaultF1F2RelayBrightnessAndReleaseOnStopWhileShortcutsStayFunctionKeys() {
        var keys: [KeyboardOutput] = []
        var media: [ConsumerKeyEvent] = []
        let engine = ActionEngine(mediaOutput: { media.append(ConsumerKeyEvent($0, pressed: $1)) },
                                  keyOutput: { keys.append($0); _ = $1 })
        engine.relay(58, pressed: true); engine.relay(58, pressed: false)
        engine.relay(59, pressed: true)
        engine.perform(MappingAction(.shortcut, "ctrl+f1"))
        engine.perform(MappingAction(.shortcut, "f2"))
        XCTAssertEqual(media, [.init(0x70, pressed: true), .init(0x70, pressed: false), .init(0x6f, pressed: true)])
        XCTAssertEqual(keys, [KeyboardOutput(58, pressed: true, modifiers: 1), KeyboardOutput(58, pressed: false, modifiers: 0),
                              KeyboardOutput(59, pressed: true, modifiers: 0), KeyboardOutput(59, pressed: false, modifiers: 0)])
        engine.stop()
        XCTAssertEqual(media.last, ConsumerKeyEvent(0x6f, pressed: false))
    }

    func testHeldBrightnessUsesRepeatTimingAndStopsRepeatingOnRelease() {
        var media: [ConsumerKeyEvent] = []
        var keys: [KeyboardOutput] = []
        let engine = ActionEngine(mediaOutput: { media.append(ConsumerKeyEvent($0, pressed: $1)) },
                                  repeatTiming: { NativeKeyboardTiming(delay: 0.4, interval: 0.4) },
                                  keyOutput: { keys.append($0); _ = $1 })
        engine.relay(58, pressed: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(media.count, 1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        XCTAssertEqual(media, Array(repeating: ConsumerKeyEvent(0x70, pressed: true), count: 2))
        engine.relay(58, pressed: false)
        let count = media.count
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        XCTAssertEqual(media.count, count)
        XCTAssertEqual(media.last, ConsumerKeyEvent(0x70, pressed: false))
        XCTAssertTrue(keys.isEmpty, "Brightness repeats must never leak raw F1 presses")
        engine.stop()
    }

    func testBrightnessSystemEventsKeepIdentityRepeatAndModifierFlags() throws {
        for (usage, code) in [(UInt16(0x6f), 2), (0x70, 3)] {
            for (pressed, repeated, state) in [(true, false, 0xa00), (true, true, 0xa01), (false, false, 0xb00)] {
                let event = try XCTUnwrap(MacMediaKeys.event(usage: usage, pressed: pressed, repeated: repeated, modifiers: 6))
                let native = try XCTUnwrap(NSEvent(cgEvent: event))
                XCTAssertEqual(native.type, .systemDefined)
                XCTAssertEqual(native.subtype.rawValue, 8)
                XCTAssertEqual(native.data1, (code << 16) | state)
                XCTAssertTrue(native.modifierFlags.contains([.shift, .option]))
                XCTAssertFalse(native.modifierFlags.contains(.function))
            }
        }
        XCTAssertNil(MacMediaKeys.event(usage: 0xffff, pressed: true))
    }

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
