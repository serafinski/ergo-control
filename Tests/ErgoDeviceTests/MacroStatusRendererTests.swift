import XCTest
import ErgoCore
@testable import ErgoDevice

final class MacroStatusRendererTests: XCTestCase {
    func testCustomColorsReachAllWaveHeadsAndWorkingHold() {
        let color = DialColor(red: 150, green: 30, blue: 210)
        for activity in [CodexActivity.working, .attention, .finished] {
            let rig = Rig()
            rig.renderer.request(color, area: .completionWave, signalID: "custom", activity: activity, speed: .quick)
            let count = activity == .working ? 3 : 5
            for _ in 0..<count { rig.renderer.pump() }
            XCTAssertTrue(rig.frames.allSatisfy { $0.contains(color) })
            XCTAssertEqual(rig.frames.map { $0.firstIndex(of: color)! }, activity == .working ? [0, 9, 18] : [0, 9, 18, 9, 0])
            rig.renderer.pump()
            if activity == .working { XCTAssertEqual(rig.frames.last, MacroStatusFrame.colors(color)) }
            if activity == .finished { XCTAssertNil(rig.saved) }
        }
    }
    func testColorEditDuringWaveContinuesAtNextColumnAndDoesNotReplayFinishedWork() {
        let rig = Rig()
        let first = DialColor(red: 150, green: 30, blue: 210), second = DialColor(red: 20, green: 200, blue: 160)
        rig.renderer.request(first, area: .completionWave, signalID: "same-work", activity: .working, speed: .quick)
        rig.renderer.pump()
        rig.renderer.request(second, area: .completionWave, signalID: "same-work", activity: .working, speed: .quick)
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.last?.firstIndex(of: second), 9)
        rig.renderer.pump(); rig.renderer.pump()
        XCTAssertEqual(rig.frames.last, MacroStatusFrame.colors(second))
        let count = rig.frames.count
        rig.renderer.request(first, area: .completionWave, signalID: "same-work", activity: .working, speed: .quick)
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, count + 1)
        XCTAssertEqual(rig.frames.last, MacroStatusFrame.colors(first), "An edited working hold must not replay the start sweep")
    }
    func testCustomPulseAndWholeKeyboardSolidUseRequestedColor() {
        let color = DialColor(red: 100, green: 200, blue: 240)
        let pulse = Rig()
        pulse.renderer.request(color, activity: .working, pulseWhileWorking: true)
        pulse.renderer.pump(); pulse.clock += 0.351; pulse.renderer.pump()
        XCTAssertEqual(pulse.frames.last?.first, DialColor(red: 75, green: 150, blue: 180))
        let solid = Rig()
        solid.renderer.request(color, area: .wholeKeyboard, activity: .attention)
        solid.renderer.pump()
        XCTAssertEqual(solid.frames.last, Array(repeating: color, count: 19))
    }
    func testEqualColorApprovalStillStopsPulsingAndCompletedWaveDoesNotReplayOnColorEdit() {
        let color = DialColor(red: 150, green: 30, blue: 210)
        let rig = Rig()
        rig.renderer.request(color, activity: .working, pulseWhileWorking: true); rig.renderer.pump()
        rig.renderer.request(color, activity: .attention, pulseWhileWorking: true); rig.renderer.pump()
        let count = rig.frames.count
        rig.clock += 1.5; rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, count); XCTAssertFalse(rig.renderer.needsTimer)
        rig.renderer.request(color, area: .completionWave, signalID: "done", activity: .finished, speed: .quick)
        for _ in 0..<5 { rig.renderer.pump() }
        rig.renderer.pump()
        let completed = rig.frames.count
        rig.renderer.request(CodexActivity.finished.color, area: .completionWave, signalID: "done", activity: .finished, speed: .quick)
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, completed)
        XCTAssertNil(rig.saved)
    }
    final class Rig {
        var effect = try! KeyboardEffect(kind: .wave)
        var saved: SavedMacroLighting?
        var operations: [String] = []
        var frames: [[DialColor]] = []
        var clock: TimeInterval = 100
        var writesBeforeSnapshot = false
        var allowed = true
        var saveFails = false
        var mismatchedReadback = false
        var rejectFrame = false
        var rejectPartial = false
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
            case .macroColor(let color):
                name = "macro"; response = Data()
                var pixels = frames.last ?? Array(repeating: MacroStatusFrame.background, count: 19)
                pixels[0] = color; frames.append(pixels)
            case .restore: name = "restore"; response = Data()
            case .experimentalWavePalette:
                XCTFail("Regular status rendering must not send the experimental Wave palette")
                name = "unexpected"; response = Data()
            }
            if name == "frame" || name == "macro" || name == "custom" { writesBeforeSnapshot = writesBeforeSnapshot || saved == nil }
            operations.append(name); beforeReply?(name)
            done(((name == "frame" || name == "macro") && rejectFrame) || (name == "macro" && rejectPartial) ? .failure(LightingLabError.invalidPacket) : .success(response))
        }, load: { [unowned self] in saved }, persist: { [unowned self] value in
            if saveFails { throw LightingLabError.invalidPacket }
            operations.append(value == nil ? "clear" : "save"); saved = value
        }, allowed: { [unowned self] in allowed }, message: { _ in }, uptime: { [unowned self] in clock })
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
            frame.count == 19 && frame.dropFirst().allSatisfy { $0 == DialColor(red: 16, green: 16, blue: 16) }
        })
        rig.renderer.request(nil); rig.renderer.pump()
        XCTAssertNil(rig.saved)
        XCTAssertEqual(rig.operations.suffix(3), ["restore", "read", "clear"])
    }

    func testAreaSwitchRepaintsSameColorAndKeepsOriginalRestorable() {
        let rig = Rig()
        let color = CodexActivity.attention.color
        rig.renderer.request(color); rig.renderer.pump()
        XCTAssertEqual(rig.frames[0].filter { $0 == color }.count, 1)
        rig.renderer.request(color, area: .wholeKeyboard); rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 2)
        XCTAssertTrue(rig.frames[1].allSatisfy { $0 == color })
        rig.renderer.pump(); XCTAssertEqual(rig.frames.count, 2, "Unchanged whole-keyboard color must coalesce")
        rig.renderer.request(nil); rig.renderer.pump()
        XCTAssertNil(rig.saved)
        XCTAssertEqual(rig.operations.suffix(3), ["restore", "read", "clear"])
    }
    func testAfterIdleNextStatusRestoresNewlyChosenNormalEffect() throws {
        let rig = Rig()
        rig.renderer.request(CodexActivity.finished.color); rig.renderer.pump()
        rig.renderer.request(nil); rig.renderer.pump()
        XCTAssertNil(rig.saved)
        rig.effect = try KeyboardEffect(kind: .breathing, colors: [DialColor(red: 200, green: 0, blue: 200)])
        rig.renderer.request(CodexActivity.working.color, area: .wholeKeyboard); rig.renderer.pump()
        XCTAssertEqual(try rig.saved?.validatedEffect(), rig.effect)
        rig.renderer.request(nil); rig.renderer.pump()
        XCTAssertNil(rig.saved)
        XCTAssertEqual(rig.operations.suffix(3), ["restore", "read", "clear"])
    }

    func testQuickCompletionRestoresOnlyAfterMacroEndpointAndDoesNotReplay() {
        let rig = Rig()
        for _ in 0..<5 {
            rig.renderer.request(CodexActivity.finished.color, area: .completionWave, signalID: "quick-done", activity: .finished, speed: .quick)
            rig.renderer.pump(); rig.clock += 0.5
            XCTAssertNotNil(rig.saved)
        }
        XCTAssertEqual(rig.frames.map { $0.firstIndex(of: CodexActivity.finished.color)! }, [0, 9, 18, 9, 0])
        rig.renderer.pump()
        XCTAssertNil(rig.saved)
        rig.renderer.request(CodexActivity.finished.color, area: .completionWave, signalID: "quick-done", activity: .finished, speed: .quick)
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 5)
    }
    func testQuickApprovalBouncesAndWorkingSettlesOnMacroBlue() {
        let rig = Rig()
        rig.renderer.request(CodexActivity.attention.color, area: .completionWave, signalID: "quick-approval", activity: .attention, speed: .quick)
        for _ in 0..<9 { rig.renderer.pump(); rig.clock += 0.5 }
        XCTAssertEqual(rig.frames.map { $0.firstIndex(of: CodexActivity.attention.color)! }, [0, 9, 18, 9, 0, 9, 18, 9, 0])
        rig.renderer.request(CodexActivity.working.color, area: .completionWave, signalID: "quick-work", activity: .working, speed: .quick)
        for _ in 0..<3 { rig.renderer.pump(); rig.clock += 0.5 }
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.suffix(4).dropLast().map { $0.firstIndex(of: CodexActivity.working.color)! }, [0, 9, 18])
        XCTAssertEqual(rig.frames.last, MacroStatusFrame.colors(CodexActivity.working.color))
        rig.renderer.request(nil); rig.renderer.pump()
        XCTAssertNil(rig.saved)
    }

    func testCompletionWavePlaysOnceAndRestoresEvenBeforeStatusExpires() {
        let rig = Rig()
        rig.renderer.request(CodexActivity.finished.color, area: .completionWave, signalID: "turn-a", activity: .finished)
        for _ in CodexStatusWave.positions(for: .finished) {
            rig.renderer.pump(); rig.clock += 0.3
        }
        XCTAssertEqual(rig.frames.count, CodexStatusWave.positions(for: .finished).count)
        XCTAssertEqual(rig.frames, (0..<7).map { CodexStatusWave.frame($0, activity: .finished) })
        XCTAssertNil(rig.renderer.desired)
        rig.renderer.pump()
        XCTAssertNil(rig.saved)
        rig.renderer.request(CodexActivity.finished.color, area: .completionWave, signalID: "turn-a", activity: .finished)
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 7, "An unchanged completion must never loop")
        rig.renderer.request(CodexActivity.finished.color, area: .completionWave, signalID: "turn-b", activity: .finished)
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 8, "A distinct completion can start a new pass")
        rig.renderer.request(nil); rig.renderer.pump()
        rig.renderer.request(CodexActivity.finished.color, area: .completionWave, signalID: "turn-a", activity: .finished)
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 8, "An older consumed completion must not replay after another chat finishes")
        XCTAssertFalse(rig.writesBeforeSnapshot)
    }
    func testCompletionWaveIsSerializedAndNewWorkCancelsIt() {
        let rig = Rig()
        rig.renderer.request(CodexActivity.finished.color, area: .completionWave, signalID: "turn-a", activity: .finished)
        rig.renderer.pump(); rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 2)
        rig.renderer.request(CodexActivity.working.color, area: .completionWave, signalID: "work-a", activity: .working)
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 3)
        XCTAssertEqual(rig.frames.last?.first, CodexActivity.working.color)
        XCTAssertTrue(rig.frames.last!.dropFirst().allSatisfy { $0 == MacroStatusFrame.background })
        rig.clock += 20; rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 4)
        XCTAssertEqual(rig.frames.last, MacroStatusFrame.colors(CodexActivity.working.color))
        rig.renderer.request(nil); rig.renderer.pump()
        XCTAssertNil(rig.saved)
    }
    func testSlowCompletionReturnsToMacrosBeforeRestoringEvenAfterStatusExpires() {
        let rig = Rig()
        rig.renderer.request(CodexActivity.finished.color, area: .completionWave, signalID: "turn-a", activity: .finished)
        for index in 0..<7 {
            // A slow/shared transport can take longer than both old time limits.
            rig.renderer.pump()
            XCTAssertNotNil(rig.saved, "Do not restore before the last frame is acknowledged")
            rig.clock += 2
            if rig.clock >= 100 + CodexStatusWave.completionWindow {
                rig.renderer.request(nil, area: .completionWave, activity: .idle, allowCompletionToFinish: true)
            }
            XCTAssertEqual(rig.frames.count, index + 1)
            XCTAssertFalse(rig.operations.contains("restore"))
        }
        XCTAssertEqual(rig.frames.map { $0.firstIndex(of: CodexActivity.finished.color)! }, [0, 6, 12, 18, 12, 6, 0])
        XCTAssertEqual(rig.frames.last?.first, CodexActivity.finished.color)
        rig.renderer.pump()
        XCTAssertNil(rig.saved)
        XCTAssertEqual(rig.operations.suffix(3), ["restore", "read", "clear"])
        rig.renderer.request(CodexActivity.finished.color, area: .completionWave, signalID: "turn-a", activity: .finished)
        XCTAssertFalse(rig.renderer.hasWork, "An expired completion must not replay")
    }

    func testExplicitDisableStillCancelsAnExpiredCompletion() {
        let rig = Rig()
        rig.renderer.request(CodexActivity.finished.color, area: .completionWave, signalID: "turn-a", activity: .finished)
        rig.renderer.pump()
        rig.clock += 10
        rig.renderer.request(nil, area: .completionWave, activity: .idle, allowCompletionToFinish: true)
        rig.renderer.request(nil) // Mappings/status lighting explicitly disabled.
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 1)
        XCTAssertNil(rig.saved)
        XCTAssertEqual(rig.operations.suffix(3), ["restore", "read", "clear"])
    }

    func testFailedFrameDuringIdleCompletionStillRestores() {
        let rig = Rig()
        rig.renderer.request(CodexActivity.finished.color, area: .completionWave, signalID: "turn-a", activity: .finished)
        rig.renderer.pump()
        rig.clock += 10
        rig.renderer.request(nil, area: .completionWave, activity: .idle, allowCompletionToFinish: true)
        rig.rejectFrame = true
        rig.renderer.pump()
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 2)
        XCTAssertNil(rig.saved)
        XCTAssertEqual(rig.operations.suffix(3), ["restore", "read", "clear"])
    }

    func testWaveCancelOrRejectedFrameStopsThePassAndRetainsVerifiedRestoration() {
        for reject in [false, true] {
            let rig = Rig(); rig.rejectFrame = reject
            if !reject {
                rig.beforeReply = { name in if name == "frame" { rig.renderer.request(nil) } }
            }
            rig.renderer.request(CodexActivity.finished.color, area: .completionWave, signalID: "turn-a", activity: .finished)
            rig.renderer.pump(); rig.beforeReply = nil
            rig.renderer.pump()
            XCTAssertEqual(rig.frames.count, 1)
            XCTAssertNil(rig.saved)
            rig.clock += 20; rig.renderer.pump()
            XCTAssertEqual(rig.frames.count, 1)
            XCTAssertEqual(rig.operations.suffix(3), ["restore", "read", "clear"])
        }
    }

    func testWorkingSweepsOncePerPhaseThenHoldsBlueUntilIdle() {
        let rig = Rig()
        for _ in 0..<4 {
            rig.renderer.request(CodexActivity.working.color, area: .completionWave, signalID: "work-a", activity: .working)
            rig.renderer.pump(); rig.clock += 0.1
        }
        XCTAssertEqual(rig.frames.map { $0.firstIndex(of: CodexActivity.working.color)! }, [0, 6, 12, 18])
        rig.renderer.pump()
        XCTAssertNotNil(rig.saved, "Keep the normal effect snapshot until work ends")
        XCTAssertEqual(rig.frames.last, MacroStatusFrame.colors(CodexActivity.working.color))
        rig.renderer.request(CodexActivity.working.color, area: .completionWave, signalID: "work-a", activity: .working)
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 5, "Ordinary tool hooks cannot repeat the working sweep or static frame")
        rig.clock += 60; rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 5, "Holding blue requires no animation stream")
        rig.renderer.request(CodexActivity.working.color, area: .completionWave, signalID: "work-after-approval", activity: .working)
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 6)
        rig.renderer.request(nil); rig.renderer.pump()
        XCTAssertNil(rig.saved)
        XCTAssertEqual(rig.operations.suffix(3), ["restore", "read", "clear"])
        XCTAssertFalse(rig.writesBeforeSnapshot)
    }
    func testApprovalBouncesWithoutEndpointPauseUntilWorkResumesThenRestore() {
        let rig = Rig()
        rig.renderer.request(CodexActivity.attention.color, area: .completionWave, signalID: "approval-a", activity: .attention)
        for _ in 0..<13 { rig.renderer.pump(); rig.clock += 0.1 }
        XCTAssertEqual(rig.frames.count, 13)
        XCTAssertEqual(rig.frames.map { $0.firstIndex(of: CodexActivity.attention.color)! }, [0, 6, 12, 18, 12, 6, 0, 6, 12, 18, 12, 6, 0])
        XCTAssertNotNil(rig.saved)
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 14, "No extra pause or duplicate endpoint when bouncing")
        XCTAssertEqual(rig.frames.last?.firstIndex(of: CodexActivity.attention.color), 6)
        rig.clock += 3600; rig.renderer.pump()
        XCTAssertNotNil(rig.renderer.desired, "Pending approval has no one-shot timeout")
        rig.renderer.request(CodexActivity.working.color, area: .completionWave, signalID: "work-resumed", activity: .working)
        for _ in 0..<4 { rig.renderer.pump(); rig.clock += 0.1 }
        XCTAssertTrue(rig.frames.suffix(4).allSatisfy { $0.contains(CodexActivity.working.color) })
        rig.renderer.pump()
        XCTAssertNotNil(rig.saved)
        XCTAssertEqual(rig.frames.last, MacroStatusFrame.colors(CodexActivity.working.color))
        let count = rig.frames.count
        rig.clock += 30; rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, count)
        rig.renderer.request(CodexActivity.finished.color, area: .completionWave, signalID: "done-after-approval", activity: .finished)
        for _ in 0..<7 { rig.renderer.pump(); rig.clock += 0.1 }
        rig.renderer.pump()
        XCTAssertNil(rig.saved)
    }
    func testDelayedWorkingSweepSettlesOnBlueWithoutDroppingRecovery() {
        let rig = Rig()
        rig.renderer.request(CodexActivity.working.color, area: .completionWave, signalID: "slow-work", activity: .working)
        rig.renderer.pump(); rig.clock += CodexStatusWave.maximumDuration
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.last, MacroStatusFrame.colors(CodexActivity.working.color))
        XCTAssertNotNil(rig.saved)
        rig.renderer.request(CodexActivity.working.color, area: .completionWave, signalID: "slow-work", activity: .working)
        XCTAssertFalse(rig.renderer.hasWork)
        rig.renderer.request(nil); rig.renderer.pump()
        XCTAssertNil(rig.saved)
    }
    func testLateApprovalAcknowledgementCannotRestartRepeatingWaveAfterCompletion() {
        let rig = Rig()
        rig.beforeReply = { name in
            if name == "frame" {
                rig.renderer.request(CodexActivity.finished.color, area: .completionWave, signalID: "done-a", activity: .finished)
            }
        }
        rig.renderer.request(CodexActivity.attention.color, area: .completionWave, signalID: "approval-a", activity: .attention)
        rig.renderer.pump(); rig.beforeReply = nil
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 2)
        XCTAssertEqual(rig.frames.last?.first, CodexActivity.finished.color)
        rig.renderer.request(nil); rig.renderer.pump()
        XCTAssertNil(rig.saved)
        rig.clock += 30; rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 2)
    }

    func testOptionalWorkingPulseStartsAfterWaveAndDoesNotReplayIt() {
        let rig = Rig()
        func working() {
            rig.renderer.request(CodexActivity.working.color, area: .completionWave,
                signalID: "pulse-work", activity: .working, pulseWhileWorking: true)
        }
        working()
        for _ in 0..<4 { rig.renderer.pump() }
        rig.renderer.pump() // First macro-only frame is bright.
        XCTAssertEqual(rig.frames.last, MacroStatusFrame.colors(CodexActivity.working.color))
        rig.clock += 0.34; working(); rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 5)
        rig.clock += 0.02; working(); rig.renderer.pump()
        let dim = rig.frames.last!
        XCTAssertEqual(dim[0], DialColor(red: 0, green: 90, blue: 191))
        XCTAssertTrue(dim.dropFirst().allSatisfy { $0 == MacroStatusFrame.background })
        rig.clock += 2.45; working(); rig.renderer.pump()
        XCTAssertEqual(rig.frames.last, MacroStatusFrame.colors(CodexActivity.working.color))
        XCTAssertEqual(rig.frames.count, 7, "Status refreshes must not restart the wave or pulse clock")
        XCTAssertNotNil(rig.saved)
    }
    func testPulseToggleOffImmediatelyRepaintsBlueAndIdleRestores() {
        let rig = Rig()
        rig.renderer.request(CodexActivity.working.color, activity: .working, pulseWhileWorking: true)
        rig.renderer.pump(); rig.clock += 1.41; rig.renderer.pump()
        XCTAssertNotEqual(rig.frames.last?.first, CodexActivity.working.color)
        rig.renderer.request(CodexActivity.working.color, activity: .working, pulseWhileWorking: false)
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.last?.first, CodexActivity.working.color)
        let count = rig.frames.count
        rig.clock += 30; rig.renderer.pump(); XCTAssertEqual(rig.frames.count, count)
        rig.renderer.request(nil); rig.renderer.pump()
        XCTAssertNil(rig.saved)
        rig.clock += 30; rig.renderer.pump(); XCTAssertEqual(rig.frames.count, count)
    }
    func testPulseSkipsMissedPhasesAndApprovalCancelsIt() {
        let rig = Rig()
        rig.renderer.request(CodexActivity.working.color, activity: .working, pulseWhileWorking: true)
        rig.renderer.pump()
        rig.clock += 141.41; rig.renderer.pump()
        XCTAssertEqual(rig.frames.count, 2, "Slow transport must not queue missed pulse frames")
        rig.renderer.request(CodexActivity.attention.color, area: .completionWave,
            signalID: "approval", activity: .attention, pulseWhileWorking: true)
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.last, CodexStatusWave.frame(0, activity: .attention))
        rig.renderer.request(nil); rig.renderer.pump()
        XCTAssertNil(rig.saved)
    }
    func testRejectedPulseRestoresWithoutFurtherPulseWrites() {
        let rig = Rig()
        rig.renderer.request(CodexActivity.working.color, activity: .working, pulseWhileWorking: true)
        rig.renderer.pump(); rig.rejectFrame = true; rig.clock += 1.41; rig.renderer.pump()
        rig.renderer.pump()
        XCTAssertNil(rig.saved)
        let count = rig.frames.count
        rig.clock += 10; rig.renderer.pump(); XCTAssertEqual(rig.frames.count, count)
    }

    func testWorkingPulseFadesThroughDarkAndBackAtTheSameSlowCycle() {
        let rig = Rig()
        rig.renderer.request(CodexActivity.working.color, activity: .working, pulseWhileWorking: true)
        rig.renderer.pump()
        for step in 1...8 {
            rig.clock = 100 + Double(step) * 0.35 + 0.001
            rig.renderer.pump()
        }
        XCTAssertEqual(rig.frames.map { $0[0].blue }, [255,191,102,38,0,38,102,191,255])
        XCTAssertEqual(rig.frames.map { $0[0].green }, [120,90,48,18,0,18,48,90,120])
        XCTAssertEqual(rig.frames[4][0], DialColor(red: 0, green: 0, blue: 0))
        XCTAssertTrue(rig.frames.allSatisfy { $0.dropFirst().allSatisfy { $0 == MacroStatusFrame.background } })
        XCTAssertNotNil(rig.saved)
        rig.renderer.request(nil); rig.renderer.pump()
        XCTAssertNil(rig.saved)
    }

    func testPulseUpdatesOnlyMacroZoneAfterOneFullFrame() {
        let rig = Rig()
        rig.renderer.request(CodexActivity.working.color, activity: .working, pulseWhileWorking: true)
        rig.renderer.pump()
        for step in 1...8 { rig.clock = 100 + Double(step) * 0.35 + 0.001; rig.renderer.pump() }
        XCTAssertEqual(rig.operations.filter { $0 == "frame" }.count, 1)
        XCTAssertEqual(rig.operations.filter { $0 == "macro" }.count, 8)
        XCTAssertTrue(rig.frames.allSatisfy { $0.dropFirst().allSatisfy { $0 == MacroStatusFrame.background } })
    }
    func testUnsupportedMacroUpdatesFallBackToFullFramesOnceAndRestore() {
        let rig = Rig(); rig.rejectPartial = true
        rig.renderer.request(CodexActivity.working.color, activity: .working, pulseWhileWorking: true)
        rig.renderer.pump(); rig.clock += 0.36; rig.renderer.pump()
        XCTAssertEqual(rig.operations.suffix(2), ["macro", "frame"])
        rig.clock += 0.35; rig.renderer.pump()
        XCTAssertEqual(rig.operations.filter { $0 == "macro" }.count, 1)
        XCTAssertNotNil(rig.saved)
        XCTAssertNotNil(rig.renderer.desired)
        rig.renderer.request(nil); rig.renderer.pump()
        XCTAssertNil(rig.saved)
    }
    func testDarkBackgroundIsOptionalAndChangingItRepaintsBeforePartialUpdates() {
        let rig = Rig()
        let black = DialColor(red: 0, green: 0, blue: 0)
        rig.renderer.request(CodexActivity.working.color, activity: .working, pulseWhileWorking: true)
        rig.renderer.pump()
        rig.renderer.request(CodexActivity.working.color, activity: .working, pulseWhileWorking: true, darkBackground: true)
        rig.renderer.pump()
        XCTAssertEqual(rig.operations.last, "frame", "The background needs a full repaint before macro-only updates")
        XCTAssertTrue(rig.frames.last!.dropFirst().allSatisfy { $0 == black })
        rig.clock += 0.36; rig.renderer.pump()
        XCTAssertEqual(rig.operations.last, "macro")
        rig.renderer.request(CodexActivity.attention.color, area: .completionWave, signalID: "approval", activity: .attention, darkBackground: true)
        rig.renderer.pump()
        XCTAssertEqual(rig.frames.last?.first, CodexActivity.attention.color)
        XCTAssertTrue(rig.frames.last!.dropFirst().allSatisfy { $0 == black })
        rig.renderer.request(nil); rig.renderer.pump()
        XCTAssertNil(rig.saved)
    }

    func testStoppingDuringPartialUpdateCannotQueueFallbackOrMorePulses() {
        let rig = Rig(); rig.rejectPartial = true
        rig.renderer.request(CodexActivity.working.color, activity: .working, pulseWhileWorking: true)
        rig.renderer.pump()
        rig.beforeReply = { name in
            if name == "macro" { rig.renderer.request(nil); rig.allowed = false }
        }
        rig.clock += 0.36; rig.renderer.pump()
        XCTAssertEqual(rig.operations.filter { $0 == "frame" }.count, 1)
        XCTAssertNotNil(rig.saved, "Keep the journal until mapping recovery owns restoration")
        rig.beforeReply = nil
        rig.renderer.restore { XCTAssertTrue($0) }
        XCTAssertNil(rig.saved)
        let count = rig.frames.count
        rig.clock += 10; rig.renderer.pump(); XCTAssertEqual(rig.frames.count, count)
    }

    func testSteadyStatusStopsFrameTimerButPulseAndRestorationKeepItAlive() {
        let rig = Rig()
        rig.renderer.request(CodexActivity.working.color, activity: .working)
        rig.renderer.pump()
        XCTAssertFalse(rig.renderer.needsTimer)
        XCTAssertNotNil(rig.saved, "A static status keeps recovery state without polling frames")
        rig.renderer.request(CodexActivity.working.color, activity: .working, pulseWhileWorking: true)
        rig.renderer.pump()
        XCTAssertFalse(rig.renderer.hasWork)
        XCTAssertTrue(rig.renderer.needsTimer, "A future pulse phase must still be scheduled")
        rig.renderer.request(nil)
        XCTAssertTrue(rig.renderer.needsTimer, "Stopping must retain the pump until restoration completes")
        rig.renderer.pump()
        XCTAssertFalse(rig.renderer.needsTimer)
        XCTAssertNil(rig.saved)
    }

}
