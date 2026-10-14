import XCTest
@testable import ErgoCore

final class NativeInputStateTests: XCTestCase {
    func testSplitKeyPacketsKeepBothHalvesHeldUntilLastRelease() {
        for (extra, usage) in [(UInt8(251), UInt8(42)), (252, 5), (253, 44)] {
            XCTAssertEqual(NativeExtraKeys.usage(for: extra), usage)
            var decoder = ExtraKeyDecoder()
            var owners = NativeKeyOwners()
            XCTAssertTrue(owners.change(usage, owner: "ordinary", pressed: true))
            let press = decoder.decode(reportID: 5, bytes: Data([5, 4, extra] + Array(repeating: 0, count: 9)))!
            XCTAssertEqual(press, [ExtraKeyEvent(key: extra, pressed: true)])
            XCTAssertFalse(owners.change(usage, owner: "extra", pressed: true))
            XCTAssertFalse(owners.change(usage, owner: "ordinary", pressed: false))
            XCTAssertEqual(decoder.decode(reportID: 5, bytes: Data([5, 4] + Array(repeating: 0, count: 10))),
                           [ExtraKeyEvent(key: extra, pressed: false)])
            XCTAssertTrue(owners.change(usage, owner: "extra", pressed: false))
        }
        XCTAssertNil(NativeExtraKeys.usage(for: 32))
        XCTAssertNil(NativeExtraKeys.usage(for: 247))
    }

    func testDuplicateAndUnownedReleasesDoNotChangeNativeKeyState() {
        var owners = NativeKeyOwners()
        XCTAssertTrue(owners.change(44, owner: "right", pressed: true))
        XCTAssertFalse(owners.change(44, owner: "right", pressed: true))
        XCTAssertFalse(owners.change(44, owner: "left", pressed: false))
        XCTAssertFalse(owners.change(5, owner: "right", pressed: false))
        XCTAssertTrue(owners.change(44, owner: "right", pressed: false))
        XCTAssertFalse(owners.change(44, owner: "right", pressed: false))
        XCTAssertTrue(owners.change(44, owner: "right", pressed: true))
    }

    func testSwitcherKeepsCommandAcrossForwardAndReverseTurns() throws {
        var switcher = DialAppSwitcher()
        XCTAssertEqual(switcher.step(try KeyChord("cmd+tab"), physicalModifiers: 0), [
            KeyboardOutput(227, pressed: true, modifiers: 8),
            KeyboardOutput(43, pressed: true, modifiers: 8),
            KeyboardOutput(43, pressed: false, modifiers: 8)])
        XCTAssertEqual(switcher.step(try KeyChord("cmd+shift+tab"), physicalModifiers: 0), [
            KeyboardOutput(43, pressed: true, modifiers: 10),
            KeyboardOutput(43, pressed: false, modifiers: 8)])
        XCTAssertTrue(switcher.isActive)
        XCTAssertEqual(switcher.finish(physicalModifiers: 0), [KeyboardOutput(227, pressed: false, modifiers: 0)])
        XCTAssertFalse(switcher.isActive)
        XCTAssertEqual(switcher.finish(physicalModifiers: 0), [])
    }

    func testSwitcherPreservesPhysicalModifiersAndIgnoresOtherShortcuts() throws {
        var switcher = DialAppSwitcher()
        for shortcut in ["ctrl+tab", "cmd+c", "cmd+alt+tab"] {
            XCTAssertNil(switcher.step(try KeyChord(shortcut), physicalModifiers: 0))
            XCTAssertFalse(switcher.isActive)
        }
        _ = switcher.step(try KeyChord("cmd+tab"), physicalModifiers: 2)
        XCTAssertEqual(switcher.finish(physicalModifiers: 2), [KeyboardOutput(227, pressed: false, modifiers: 2)])
        _ = switcher.step(try KeyChord("cmd+tab"), physicalModifiers: 128)
        XCTAssertEqual(switcher.finish(physicalModifiers: 128), [])
        XCTAssertFalse(switcher.isActive)
    }
}
