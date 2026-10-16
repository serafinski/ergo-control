import XCTest
import ServiceManagement
@testable import ErgoControl

final class HelperRegistrationTests: XCTestCase {
    final class Registration: HelperDaemonRegistration {
        var status: SMAppService.Status = .enabled
        var actions: [String] = []
        var failRemoval = false
        var keepRegistration = false
        func register() throws { actions.append("register"); status = .enabled }
        func unregister() throws {
            actions.append("unregister")
            if failRemoval { throw NSError(domain: "test", code: 1) }
            if !keepRegistration { status = .notRegistered }
        }
    }
    func packages() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["ErgoInputHelper-Install.pkg", "ErgoInputHelper-Uninstall.pkg"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }
    func testLocalRepairRemovesPersistentRegistrationBeforeOpeningInstaller() throws {
        let registration = Registration()
        let helper = FullControlHelper(service: registration, localOverride: { true }, installedOverride: { true },
                                       packageDirectory: try packages(), openInstaller: { url in
            registration.actions.append(url.lastPathComponent); return true
        })
        XCTAssertTrue(helper.needsStartupRepair)
        XCTAssertFalse(helper.enabled, "Matching bytes on disk do not prove the running job uses that path")
        try helper.register()
        XCTAssertEqual(registration.actions, ["unregister", "ErgoInputHelper-Install.pkg"])
        helper.refresh()
        XCTAssertTrue(helper.enabled)
        XCTAssertFalse(helper.needsStartupRepair)
    }
    func testRemovalFailureOrStillRegisteredNeverOpensInstaller() throws {
        for throwsError in [true, false] {
            let registration = Registration()
            registration.failRemoval = throwsError; registration.keepRegistration = !throwsError
            let helper = FullControlHelper(service: registration, localOverride: { true }, installedOverride: { true },
                                           packageDirectory: try packages(), openInstaller: { _ in
                XCTFail("Do not install over a persistent registration that has not been removed"); return false
            })
            XCTAssertThrowsError(try helper.register())
            XCTAssertTrue(helper.needsStartupRepair)
        }
    }
    func testCleanLocalInstallDoesNotRegisterBundledDaemonAndUninstallRemovesLegacyEntry() throws {
        let registration = Registration(); registration.status = .notRegistered
        let helper = FullControlHelper(service: registration, localOverride: { true }, installedOverride: { true },
                                       packageDirectory: try packages(), openInstaller: { url in
            registration.actions.append(url.lastPathComponent); return true
        })
        try helper.register()
        XCTAssertEqual(registration.actions, ["ErgoInputHelper-Install.pkg"])
        registration.status = .requiresApproval
        try helper.unregister()
        XCTAssertEqual(registration.actions, ["ErgoInputHelper-Install.pkg", "unregister", "ErgoInputHelper-Uninstall.pkg"])
    }
    func testDeveloperIDRouteKeepsServiceManagementRegistration() throws {
        let registration = Registration(); registration.status = .notRegistered
        let helper = FullControlHelper(service: registration, localOverride: { false }, installedOverride: { false },
                                       openInstaller: { _ in XCTFail("Unexpected installer"); return false })
        XCTAssertFalse(helper.needsStartupRepair)
        try helper.register()
        XCTAssertTrue(helper.enabled)
        try helper.unregister()
        XCTAssertEqual(registration.actions, ["register", "unregister"])
    }
}
