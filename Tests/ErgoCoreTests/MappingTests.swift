import XCTest
@testable import ErgoCore

final class MappingTests: XCTestCase {
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
