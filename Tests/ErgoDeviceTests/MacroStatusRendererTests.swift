import XCTest
import ErgoCore
@testable import ErgoDevice

final class MacroStatusRendererTests: XCTestCase {
    final class Rig {
        let effect = try! KeyboardEffect(kind: .wave)
        var saved: SavedMacroLighting?
        var operations: [String] = []
        var frames: [[DialColor]] = []
        var writesBeforeSnapshot = false
        var allowed = true
        var saveFails = false
        var mismatchedReadback = false
        var rejectFrame = false
        var beforeReply: ((String) -> Void)?
        lazy var renderer = MacroStatusRenderer(command: { [unowned self] command, region, done in
            let name: String; let response: Data
            switch command {
            case .readRegions: name = "regions"; response = Data([5])
            case .readEffect: name = "read"; response = mismatchedReadback ? Data([3,0,0,0]) : effect.payload
            case .selectCustom: name = "custom"; response = Data()
            case .frame(let colors):
                name = "frame"; response = Data()
                frames.append(colors)
                XCTAssertEqual(colors.count, 19)
            case .restore: name = "restore"; response = Data()
            }
            if name == "frame" || name == "custom" { writesBeforeSnapshot = writesBeforeSnapshot || saved == nil }
            operations.append(name); beforeReply?(name)
            done(name == "frame" && rejectFrame ? .failure(LightingLabError.invalidPacket) : .success(response))
        }, load: { [unowned self] in saved }, persist: { [unowned self] value in
            if saveFails { throw LightingLabError.invalidPacket }
            operations.append(value == nil ? "clear" : "save"); saved = value
        }, allowed: { [unowned self] in allowed }, message: { _ in })
    }
    func testSnapshotPrecedesEveryWriteAndFramesAreCoalesced() throws {
        let rig = Rig()
        rig.renderer.desired = CodexActivity.working.color; rig.renderer.pump()
        XCTAssertEqual(rig.operations, ["regions", "read", "save", "custom", "frame"])
        XCTAssertFalse(rig.writesBeforeSnapshot)
        rig.renderer.pump()
        XCTAssertEqual(rig.operations.count, 5)
        rig.renderer.desired = CodexActivity.attention.color; rig.renderer.pump()
        XCTAssertEqual(rig.operations.last, "frame")
        XCTAssertEqual(rig.operations.count, 6)
    }
    func testNoWritesWhenSnapshotCannotBeSaved() {
        let rig = Rig(); rig.saveFails = true
        rig.renderer.desired = CodexActivity.working.color; rig.renderer.pump()
        XCTAssertEqual(rig.operations, ["regions", "read"])
        XCTAssertNil(rig.saved)
    }
    func testDisableRestoresAndVerifiesBeforeRemovingRecovery() throws {
        let rig = Rig(); rig.renderer.desired = CodexActivity.working.color; rig.renderer.pump()
        rig.operations = []
        rig.renderer.desired = nil; rig.renderer.pump()
        XCTAssertEqual(rig.operations, ["restore", "read", "clear"])
        XCTAssertNil(rig.saved)
    }
    func testMismatchedReadbackRetainsRecoveryAndBacksOff() throws {
        let rig = Rig(); rig.saved = try SavedMacroLighting(region: 5, effect: rig.effect)
        rig.mismatchedReadback = true
        rig.renderer.pump()
        XCTAssertNotNil(rig.saved)
        XCTAssertEqual(rig.operations, ["restore", "read"])
        XCTAssertFalse(rig.renderer.hasWork)
    }
    func testMappingStopCancelsFrameButKeepsSnapshotForRecovery() {
        let rig = Rig()
        rig.beforeReply = { if $0 == "custom" { rig.allowed = false } }
        rig.renderer.desired = CodexActivity.working.color; rig.renderer.pump()
        XCTAssertNotNil(rig.saved)
        XCTAssertFalse(rig.operations.contains("frame"))
        XCTAssertFalse(rig.renderer.busy)
        rig.beforeReply = nil
        var restored = false
        rig.renderer.restore { restored = $0 }
        XCTAssertTrue(restored)
        XCTAssertNil(rig.saved)
    }
    func testRejectedFrameRestoresWithoutRetryingCustomWrites() {
        let rig = Rig(); rig.rejectFrame = true
        rig.renderer.desired = CodexActivity.working.color; rig.renderer.pump()
        XCTAssertNil(rig.renderer.desired)
        rig.renderer.pump()
        XCTAssertNil(rig.saved)
        XCTAssertEqual(rig.operations.suffix(3), ["restore", "read", "clear"])
    }
    func testNewStatusCannotDisplaceRestorationAfterRejectedFrame() {
        let rig = Rig(); rig.rejectFrame = true
        rig.renderer.desired = CodexActivity.working.color; rig.renderer.pump()
        rig.renderer.desired = CodexActivity.attention.color
        rig.renderer.pump()
        XCTAssertNil(rig.saved)
        XCTAssertEqual(rig.operations.suffix(3), ["restore", "read", "clear"])
        XCTAssertFalse(rig.renderer.hasWork)
    }
    func testNewStatusDuringSetupUsesLatestColorAndCannotOverlapTheQueue() {
        let rig = Rig()
        rig.beforeReply = { name in
            if name == "custom" {
                rig.renderer.desired = CodexActivity.attention.color
                rig.renderer.pump() // No reentrant read or second frame while busy.
            }
        }
        rig.renderer.desired = CodexActivity.working.color; rig.renderer.pump()
        XCTAssertEqual(rig.operations, ["regions", "read", "save", "custom", "frame"])
        XCTAssertFalse(rig.renderer.hasWork)
    }
    func testCrashRecoveryNeedsNoDesiredColorOrActiveLease() throws {
        let rig = Rig(); rig.saved = try SavedMacroLighting(region: 5, effect: rig.effect)
        rig.allowed = false
        rig.renderer.pump(); XCTAssertTrue(rig.operations.isEmpty)
        var restored = false
        rig.renderer.restore { restored = $0 }
        XCTAssertTrue(restored)
        XCTAssertEqual(rig.operations, ["restore", "read", "clear"])
    }
    func testLegacyModeJournalRemainsDecodableAndNewSnapshotRoundTrips() throws {
        let id = UUID()
        var mode = try JSONDecoder().decode(SavedMode.self, from: JSONSerialization.data(withJSONObject:
            ["peripheral": id.uuidString, "mode": 0, "parameter": 0]))
        XCTAssertNil(mode.macroLighting)
        mode.macroLighting = try SavedMacroLighting(region: 5, effect: KeyboardEffect(kind: .wave))
        let restored = try JSONDecoder().decode(SavedMode.self, from: JSONEncoder().encode(mode))
        XCTAssertEqual(restored.macroLighting, mode.macroLighting)
        XCTAssertEqual(restored.peripheral, id)
    }
    func testStatusSequenceChangesOnlyMacroZoneAndRestoresOriginalEffect() {
        let rig = Rig()
        let states: [CodexActivity] = [.working, .attention, .finished, .idle]
        for state in states {
            rig.renderer.request(state.color); rig.renderer.pump()
        }
        XCTAssertEqual(rig.frames.map { $0[0] }, states.map(\.color))
        XCTAssertTrue(rig.frames.allSatisfy { frame in
            frame.count == 19 && frame.dropFirst().allSatisfy { $0 == DialColor(red: 160, green: 160, blue: 160) }
        })
        rig.renderer.request(nil); rig.renderer.pump()
        XCTAssertNil(rig.saved)
        XCTAssertEqual(rig.operations.suffix(3), ["restore", "read", "clear"])
    }

}
