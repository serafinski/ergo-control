import XCTest
@testable import ErgoCore

final class MappingResolverTests: XCTestCase {
    func testExplicitCodexKeysStayCodexWithClaudeAutomaticDefaults() {
        var profile = MappingProfile()
        for slot in 1...5 { profile.mappings["extra:\(slot + 31)"] = MappingAction(.codexChat, String(slot)) }
        let assignments = MappingResolver.macroKeys(profile: profile, alternateLayer: false) { _ in
            MappingAction(.claudeChat, "1")
        }
        XCTAssertEqual(assignments.map(\.id), [1, 2, 3, 4, 5])
        XCTAssertEqual(assignments.map(\.provider), Array(repeating: .codex, count: 5))
        XCTAssertEqual(assignments.compactMap(\.slot), [1, 2, 3, 4, 5])
        XCTAssertTrue(assignments.allSatisfy { $0.mapping.origin == .standardLayer })
    }

    func testMixedMappingsKeepKeyNumbersSeparateFromDestinationSlots() {
        var profile = MappingProfile()
        profile.mappings["extra:32"] = MappingAction(.codexChat, "3")
        profile.mappings["extra:33"] = MappingAction(.disabled)
        profile.mappings["extra:34"] = MappingAction(.text, "Example")
        profile.mappings["extra:35"] = MappingAction(.claudeChat, "1")
        let keys = MappingResolver.macroKeys(profile: profile, alternateLayer: false)
        XCTAssertEqual(keys.filter { $0.provider == .codex }.map(\.id), [1])
        XCTAssertEqual(keys[0].slot, 3)
        XCTAssertEqual(keys.filter { $0.provider == .claude }.map(\.id), [4])
        XCTAssertEqual(keys[3].slot, 1)
        XCTAssertNil(keys[1].provider); XCTAssertNil(keys[2].provider); XCTAssertNil(keys[4].provider)
        XCTAssertEqual(keys[4].mapping.origin, .keyboardDefault)
    }

    func testAlternateOverridesAndDefaultInheritsBeforeAutomaticFallback() {
        var profile = MappingProfile()
        profile.mappings["extra:32"] = MappingAction(.codexChat, "4")
        profile.mappings["extra:33"] = MappingAction(.codexChat, "2")
        profile.alternate["extra:32"] = MappingAction(.claudeChat, "1")
        profile.alternate["extra:33"] = MappingAction()
        profile.alternate["extra:34"] = MappingAction(.disabled)
        let fallback = MappingAction(.claudeChat, "5")
        let keys = MappingResolver.macroKeys(profile: profile, alternateLayer: true) { _ in fallback }
        XCTAssertEqual(keys[0].mapping.action, MappingAction(.claudeChat, "1"))
        XCTAssertEqual(keys[0].mapping.origin, .alternateLayer)
        XCTAssertEqual(keys[1].mapping.action, profile.mappings["extra:33"])
        XCTAssertEqual(keys[1].mapping.origin, .standardLayer)
        XCTAssertEqual(keys[2].mapping.action.kind, .disabled)
        XCTAssertNil(keys[2].provider)
        XCTAssertEqual(keys[3].mapping.action, fallback)
        XCTAssertEqual(keys[3].mapping.origin, .automatic)
        let standard = MappingResolver.macroKeys(profile: profile, alternateLayer: false) { _ in fallback }
        XCTAssertEqual(standard[0].provider, .codex)
        XCTAssertEqual(standard[2].mapping.origin, .automatic)
    }

    func testInvalidExplicitChatSlotDoesNotBecomeAnAutomaticAssignment() {
        var profile = MappingProfile()
        for (key, value) in zip(32...36, ["0", "6", "", "invalid", "-1"]) {
            profile.mappings["extra:\(key)"] = MappingAction(.claudeChat, value)
        }
        let keys = MappingResolver.macroKeys(profile: profile, alternateLayer: false) { _ in MappingAction(.codexChat, "1") }
        XCTAssertTrue(keys.allSatisfy { $0.provider == nil && $0.slot == nil })
        XCTAssertTrue(keys.allSatisfy { $0.mapping.origin == .standardLayer })
    }
}
