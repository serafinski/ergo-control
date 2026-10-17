import XCTest
import ErgoCore
@testable import ErgoDevice

final class KeyboardPowerManagerTests: XCTestCase {
    final class Rig {
        var raw: UInt8 = 13
        var dim = KeyboardDimming(enabled: true, seconds: 300)
        var sleep = KeyboardSleep(enabled: true, seconds: 900)
        var id: UUID? = UUID()
        var journal: SavedKeyboardBrightness?
        var commands: [String] = []
        var saveFails = false
        var removeFails = false
        var reject: String?
        var malformed: String?
        var ignoreDimmingWrite = false
        var beforeReply: ((String) -> Void)?
        var inFlight = false
        var next: UInt8 = 0
        var loadFails = false
        lazy var manager: KeyboardPowerManager = KeyboardPowerManager(send: { [unowned self] request, done in
            XCTAssertFalse(inFlight, "Commands must be serialized")
            inFlight = true
            let name = String(format: "%02x/%02x", request.header[4], request.header[5])
            commands.append(name)
            let bytes = Array(request.payload)
            var response = Data()
            if reject == name { inFlight = false; done(.failure(LightingLabError.message("Rejected"))); return }
            switch name {
            case "10/85": response = Data([raw])
            case "10/05":
                XCTAssertEqual(bytes.count, 1)
                if manager.suppressed && bytes[0] == 0 && raw != 0 { XCTAssertNotNil(journal, "Journal must be durable before blackout") }
                raw = bytes[0]
            case "05/8a": response = Data([dim.enabled ? 1 : 0, UInt8(dim.seconds & 255), UInt8(dim.seconds >> 8), dim.percentage])
            case "05/0a": if !ignoreDimmingWrite { dim = try! KeyboardDimming(payload: request.payload) }
            case "05/84": response = Data([UInt8(sleep.seconds & 255), UInt8(sleep.seconds >> 8)])
            case "05/04": sleep.seconds = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
            case "05/87": response = Data([sleep.enabled ? 1 : 0])
            case "05/07": sleep.enabled = bytes[0] == 1
            default: XCTFail("Unexpected command \(name)")
            }
            if malformed == name { response = Data() }
            beforeReply?(name)
            inFlight = false; done(.success(response))
        }, transaction: { [unowned self] in next = next == 31 ? 1 : next + 1; return next },
        identity: { [unowned self] in id }, load: { [unowned self] in
            if loadFails { throw LightingLabError.invalidPacket }; return journal
        }, persist: { [unowned self] value in
            if value != nil && saveFails { throw LightingLabError.message("Disk full") }
            if value == nil && removeFails { throw LightingLabError.message("Cannot remove journal") }
            journal = value
        }, changed: {})
        func read() { manager.requestRead(); manager.pump() }
    }
    func testReadsSettingsWithoutAnyWrites() {
        let rig = Rig(); rig.read()
        XCTAssertEqual(rig.commands, ["10/85","05/8a","05/84","05/87"])
        XCTAssertEqual(rig.manager.settings?.brightness, 13)
        XCTAssertEqual(rig.manager.settings?.dimming, rig.dim)
        XCTAssertEqual(rig.manager.settings?.sleep, rig.sleep)
        XCTAssertFalse(rig.manager.busy)
    }
    func testUserSettingsWriteAndReadbackAllRequestedValues() {
        let rig = Rig()
        let dim = KeyboardDimming(enabled: true, seconds: 60)
        let sleep = KeyboardSleep(enabled: true, seconds: 180)
        rig.manager.apply(KeyboardPowerChanges(brightness: 76, dimming: dim, sleep: sleep)); rig.manager.pump()
        XCTAssertEqual(rig.manager.settings, KeyboardPowerSettings(brightness: 76, dimming: dim, sleep: sleep))
        XCTAssertTrue(rig.manager.message.contains("applied and verified"))
        XCTAssertNil(rig.journal, "Persistent user choices must not be undone on quit")
        XCTAssertLessThan(rig.commands.firstIndex(of: "05/04")!, rig.commands.firstIndex(of: "05/07")!)
    }
    func testDisablingSleepHappensBeforeChangingItsTimer() {
        let rig = Rig(); rig.manager.apply(KeyboardPowerChanges(sleep: KeyboardSleep(enabled: false, seconds: 300))); rig.manager.pump()
        XCTAssertLessThan(rig.commands.firstIndex(of: "05/07")!, rig.commands.firstIndex(of: "05/04")!)
        XCTAssertFalse(rig.sleep.enabled)
    }
    func testUnchangedApplyDoesNotWriteAnything() {
        let rig = Rig()
        rig.manager.apply(KeyboardPowerChanges(brightness: rig.raw, dimming: rig.dim, sleep: rig.sleep)); rig.manager.pump()
        XCTAssertTrue(rig.commands.allSatisfy { ["10/85","05/8a","05/84","05/87"].contains($0) })
    }
    func testMismatchAndPartialFailureNeverClaimSuccess() {
        let rig = Rig(); rig.ignoreDimmingWrite = true
        rig.manager.apply(KeyboardPowerChanges(dimming: KeyboardDimming(enabled: true, seconds: 60))); rig.manager.pump()
        XCTAssertTrue(rig.manager.message.contains("different settings"))
        XCTAssertEqual(rig.manager.settings?.dimming.seconds, 300)
        rig.reject = "05/04"
        rig.manager.apply(KeyboardPowerChanges(sleep: KeyboardSleep(enabled: false, seconds: 300))); rig.manager.pump()
        XCTAssertTrue(rig.manager.message.contains("incomplete"))
        XCTAssertNil(rig.manager.settings)
        XCTAssertFalse(rig.sleep.enabled)
    }
    func testMalformedReadDoesNotPublishGuessedValues() {
        for query in ["10/85","05/8a","05/84","05/87"] {
            let rig = Rig(); rig.malformed = query; rig.read()
            XCTAssertNil(rig.manager.settings)
            XCTAssertFalse(rig.manager.busy)
        }
    }
    func testBlackoutJournalsExactRawBrightnessAndRestoresItOnWake() {
        let rig = Rig()
        rig.manager.setSuppressed(true); rig.manager.pump()
        XCTAssertEqual(rig.raw, 0)
        XCTAssertEqual(rig.journal, SavedKeyboardBrightness(peripheral: rig.id!, brightness: 13))
        XCTAssertFalse(rig.manager.needsTimer)
        rig.manager.setSuppressed(false); rig.manager.pump()
        XCTAssertEqual(rig.raw, 13)
        XCTAssertNil(rig.journal)
        XCTAssertFalse(rig.manager.hasWork)
        XCTAssertFalse(rig.manager.needsTimer)
    }
    func testAlreadyOffBrightnessStaysOffAndDoesNotLoopOnWake() {
        let rig = Rig(); rig.raw = 0
        rig.manager.setSuppressed(true); rig.manager.pump()
        XCTAssertNil(rig.journal)
        rig.manager.setSuppressed(false); rig.manager.pump()
        XCTAssertEqual(rig.raw, 0)
        XCTAssertEqual(rig.commands, ["10/85"])
        XCTAssertFalse(rig.manager.hasWork)
    }
    func testJournalSaveFailurePreventsBlackoutAndBacksOff() {
        let rig = Rig(); rig.saveFails = true
        rig.manager.setSuppressed(true); rig.manager.pump()
        XCTAssertEqual(rig.raw, 13)
        XCTAssertFalse(rig.commands.contains("10/05"))
        XCTAssertFalse(rig.manager.hasWork)
    }
    func testFailedRestorationRetainsRecoveryRecord() {
        let rig = Rig(); rig.manager.setSuppressed(true); rig.manager.pump()
        rig.removeFails = true; rig.manager.setSuppressed(false); rig.manager.pump()
        XCTAssertEqual(rig.raw, 13)
        XCTAssertNotNil(rig.journal)
        XCTAssertTrue(rig.manager.restorationOwed)
        XCTAssertFalse(rig.manager.hasWork)
    }
    func testCrashRecoveryRestoresBeforeReadingSettings() {
        let rig = Rig(); rig.journal = SavedKeyboardBrightness(peripheral: rig.id!, brightness: 26); rig.raw = 0
        rig.manager.requestRead(); rig.manager.pump()
        XCTAssertEqual(rig.raw, 26); XCTAssertNil(rig.journal)
        XCTAssertEqual(rig.commands, ["10/05","10/85"])
        rig.manager.pump()
        XCTAssertEqual(rig.manager.settings?.brightness, 26)
    }
    func testDifferentKeyboardCannotReceiveRecoveryWrite() {
        let rig = Rig(); rig.journal = SavedKeyboardBrightness(peripheral: UUID(), brightness: 26)
        rig.manager.pump()
        XCTAssertTrue(rig.commands.isEmpty)
        XCTAssertNotNil(rig.journal)
    }
    func testIdentityChangeInReadChainStopsBeforeAnyWrite() {
        let rig = Rig(); rig.beforeReply = { if $0 == "05/8a" { rig.id = UUID() } }
        rig.manager.apply(KeyboardPowerChanges(brightness: 100)); rig.manager.pump()
        XCTAssertFalse(rig.commands.contains("10/05"))
        XCTAssertFalse(rig.manager.message.contains("applied and verified"))
    }
    func testBrightnessChangeDuringBlackoutUpdatesRestoreTargetWithoutLightingKeys() {
        let rig = Rig(); rig.manager.setSuppressed(true); rig.manager.pump()
        let before = rig.commands.filter { $0 == "10/05" }.count
        rig.manager.apply(KeyboardPowerChanges(brightness: 51)); rig.manager.pump()
        XCTAssertEqual(rig.raw, 0)
        XCTAssertEqual(rig.journal?.brightness, 51)
        XCTAssertEqual(rig.commands.filter { $0 == "10/05" }.count, before)
        rig.manager.setSuppressed(false); rig.manager.pump()
        XCTAssertEqual(rig.raw, 51)
    }
    func testQuitRestoresBlackoutInsteadOfApplyingQueuedUserSettings() {
        let rig = Rig(); rig.manager.setSuppressed(true); rig.manager.pump()
        rig.manager.apply(KeyboardPowerChanges(brightness: 200))
        rig.manager.prepareToQuit(); rig.manager.pump()
        XCTAssertEqual(rig.raw, 13); XCTAssertNil(rig.journal)
        XCTAssertFalse(rig.manager.hasWork)
    }
    func testCancelledOffRequestBeforeReadbackDoesNotFlashBlack() {
        let rig = Rig(); rig.beforeReply = { _ in rig.manager.setSuppressed(false) }
        rig.manager.setSuppressed(true); rig.manager.pump()
        XCTAssertEqual(rig.raw, 13); XCTAssertNil(rig.journal)
        XCTAssertFalse(rig.commands.contains("10/05"))
    }
    func testInvalidJournalIsPreservedAndBlocksWrites() {
        let rig = Rig(); rig.loadFails = true
        rig.manager.apply(KeyboardPowerChanges(brightness: 200)); rig.manager.pump()
        XCTAssertTrue(rig.commands.isEmpty)
        XCTAssertTrue(rig.manager.message.contains("invalid"))
    }
    func testWakeDuringOffWriteRestoresInsteadOfLosingTheJournal() {
        let rig = Rig()
        rig.beforeReply = { name in if name == "10/05" && rig.raw == 0 { rig.manager.setSuppressed(false) } }
        rig.manager.setSuppressed(true); rig.manager.pump()
        XCTAssertNotNil(rig.journal)
        XCTAssertFalse(rig.manager.offVerified)
        XCTAssertTrue(rig.manager.hasWork)
        rig.beforeReply = nil; rig.manager.pump()
        XCTAssertEqual(rig.raw, 13); XCTAssertNil(rig.journal)
    }
    func testQuitDuringOffWriteStillRestoresBeforeFinishing() {
        let rig = Rig()
        rig.beforeReply = { name in if name == "10/05" && rig.raw == 0 { rig.manager.prepareToQuit() } }
        rig.manager.setSuppressed(true); rig.manager.pump()
        XCTAssertTrue(rig.manager.restorationOwed)
        rig.beforeReply = nil; rig.manager.pump()
        XCTAssertEqual(rig.raw, 13); XCTAssertNil(rig.journal)
        XCTAssertFalse(rig.manager.hasWork)
    }

}
