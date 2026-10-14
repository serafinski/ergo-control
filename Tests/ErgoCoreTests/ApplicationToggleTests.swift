import XCTest
@testable import ErgoCore

final class ApplicationToggleTests: XCTestCase {
    func testClosedBackgroundAndMinimizedAppsAreShown() {
        XCTAssertEqual(ApplicationToggleDecision.resolve(isRunning: false, isFrontmost: false, hasVisibleWindow: false), .launch)
        XCTAssertEqual(ApplicationToggleDecision.resolve(isRunning: true, isFrontmost: false, hasVisibleWindow: true), .show)
        XCTAssertEqual(ApplicationToggleDecision.resolve(isRunning: true, isFrontmost: false, hasVisibleWindow: false), .show)
        // macOS can leave an app frontmost after its last window was minimized.
        XCTAssertEqual(ApplicationToggleDecision.resolve(isRunning: true, isFrontmost: true, hasVisibleWindow: false), .show)
        XCTAssertEqual(ApplicationToggleDecision.resolve(isRunning: true, isFrontmost: true, hasVisibleWindow: true), .minimize)
    }

    func testToggleMappingRoundTripsWithoutChangingOpenApplication() throws {
        var settings = MappingConfiguration()
        settings.profiles[0].mappings["extra:247"] = MappingAction(.toggleApplication, "/Applications/Codex.app")
        settings.profiles[0].mappings["extra:32"] = MappingAction(.application, "/Applications/Example.app")
        let decoded = try JSONDecoder().decode(MappingConfiguration.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.profiles[0].mappings["extra:32"]?.kind, .application)
    }
}
