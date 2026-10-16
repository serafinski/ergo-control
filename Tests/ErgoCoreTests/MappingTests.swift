import XCTest
@testable import ErgoCore

final class MappingTests: XCTestCase {
    func testFunctionKeyProvidersDefaultToAppleAndPreserveLegacyRaycastOnUpgrade() throws {
        var config = MappingConfiguration()
        XCTAssertEqual(config.functionKeys.search, .spotlight)
        XCTAssertEqual(config.functionKeys.dictation, .apple)
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(config)) as? [String: Any])
        legacy.removeValue(forKey: "functionKeys")
        let migrated = try decoder.decode(MappingConfiguration.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(migrated.functionKeys.search, .raycast)
        XCTAssertEqual(migrated.functionKeys.dictation, .apple)
        XCTAssertEqual(migrated.profiles, config.profiles)
        config.functionKeys = FunctionKeyPreferences(search: .raycast, dictation: .fluidVoice, fluidVoiceShortcut: "ctrl+shift+space")
        XCTAssertEqual(try decoder.decode(MappingConfiguration.self, from: encoder.encode(config)), config)
    }
    func testFluidVoiceShortcutAcceptsSidedModifiersAndChordsWithoutPlainTextKeys() throws {
        let modifier = try DictationTrigger(" RightOption ")
        XCTAssertEqual(modifier.modifiers, 64); XCTAssertNil(modifier.usage)
        let chord = try DictationTrigger("ctrl+shift+space")
        XCTAssertEqual(chord.modifiers, 3); XCTAssertEqual(chord.usage, 44)
        XCTAssertEqual(try DictationTrigger("f13").usage, 104)
        for value in ["d", "space", "", "unknown", "super+space"] { XCTAssertThrowsError(try DictationTrigger(value)) }
    }
    func testProfilesRoundTripAndAutoSwitchFallback() throws {
        var config = MappingConfiguration()
        var editor = MappingProfile(name: "Editor"); editor.applicationIDs = ["example.editor"]
        editor.mappings["extra:32"] = MappingAction(.macro, "cmd+c\nwait 200\ncmd+v")
        config.profiles.append(editor)
        XCTAssertEqual(config.profile(for: "example.editor").id, editor.id)
        XCTAssertEqual(config.profile(for: "other").id, config.manualProfileID)
        config.autoSwitch = false
        XCTAssertEqual(config.profile(for: "example.editor").id, config.manualProfileID)
        XCTAssertEqual(try JSONDecoder().decode(MappingConfiguration.self, from: JSONEncoder().encode(config)), config)
    }
    func testShortcutAndBoundedMacroValidation() throws {
        let chord = try KeyChord("cmd+shift+c")
        XCTAssertEqual(chord.usage, 6); XCTAssertEqual(chord.modifiers, 10)
        XCTAssertEqual(try MacroStep.parse("cmd+c\nwait 200\ntext copied\ncmd+v").count, 4)
        XCTAssertThrowsError(try KeyChord("unknown+c"))
        XCTAssertThrowsError(try MacroStep.parse("wait -1"))
        XCTAssertThrowsError(try MacroStep.parse(Array(repeating: "wait 10000", count: 7).joined(separator: "\n")))
    }
}
