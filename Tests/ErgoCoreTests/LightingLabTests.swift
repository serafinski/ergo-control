import XCTest
@testable import ErgoCore

final class LightingLabTests: XCTestCase {
    private let black = DialColor(red: 0, green: 0, blue: 0)

    func testMacroPatternsOnlyAddressTheSharedColumn() throws {
        for pattern in [LightingLabPattern.macroSolid, .macroPulse, .macroColors] {
            for time in stride(from: 0.0, through: 10, by: 0.1) {
                let colors = try pattern.frame(at: time)
                XCTAssertEqual(colors.count, 19)
                XCTAssertTrue(colors.dropFirst().allSatisfy { $0 == black })
            }
        }
        XCTAssertEqual(try LightingLabPattern.macroPulse.frame(at: 0)[0], black)
        XCTAssertEqual(try LightingLabPattern.macroPulse.frame(at: 1)[0].blue, 255)
        XCTAssertNotEqual(try LightingLabPattern.macroColors.frame(at: 0)[0],
                          try LightingLabPattern.macroColors.frame(at: 2)[0])
    }

    func testScanChaseAndProgressCoverRealZonesWithoutExtraKeys() throws {
        for index in 0..<19 {
            let frame = try LightingLabPattern.scan.frame(at: (Double(index) + 0.1) / 5)
            XCTAssertEqual(frame.filter { $0 != black }.count, 1)
            XCTAssertNotEqual(frame[index], black)
        }
        let chase = try LightingLabPattern.chase.frame(at: 0)
        XCTAssertEqual(chase.filter { $0 != black }.count, 4)
        XCTAssertGreaterThan(chase[0].blue, chase[18].blue)
        XCTAssertGreaterThan(chase[18].blue, chase[17].blue)
        XCTAssertEqual(try LightingLabPattern.progress.frame(at: 0).filter { $0 != black }.count, 0)
        XCTAssertEqual(try LightingLabPattern.progress.frame(at: 3.81).filter { $0 != black }.count, 19)
        for pattern in LightingLabPattern.allCases where pattern.requiresZones {
            XCTAssertEqual(try pattern.frame(at: 1e100).count, 19)
            XCTAssertThrowsError(try pattern.frame(at: -.infinity))
            XCTAssertThrowsError(try pattern.frame(at: .nan))
            XCTAssertThrowsError(try pattern.frame(at: -1))
        }
        XCTAssertThrowsError(try LightingLabPattern.presets.frame(at: 0))
        let rainbow = try LightingLabPattern.rainbow.frame(at: 0)
        XCTAssertGreaterThan(Set(rainbow.map { Array($0.bytes) }).count, 10)
        XCTAssertNotEqual(rainbow, try LightingLabPattern.rainbow.frame(at: 1))
    }

    func testUSBFrameHasCorrectProtocolFamilyBoundariesAndChecksum() throws {
        let colors = try LightingLabPattern.macroSolid.frame(at: 0)
        let data = try USBLightingCommand.frame(colors).request(transaction: 3)
        XCTAssertEqual(data.count, 90)
        XCTAssertEqual(Array(data.prefix(13)), [0,3,0,0,0,62,15,3,0,0,0,0,18])
        XCTAssertEqual(Array(data[13..<16]), [0,180,255])
        XCTAssertTrue(data[16..<88].allSatisfy { $0 == 0 })
        XCTAssertEqual(data[88], data[2..<88].reduce(0, ^))
        XCTAssertThrowsError(try USBLightingCommand.frame(Array(colors.dropLast())))
        XCTAssertThrowsError(try USBLightingCommand.frame(colors + [black]))
        XCTAssertThrowsError(try USBLightingCommand.customEffect.request(transaction: 0))
        XCTAssertThrowsError(try USBLightingCommand.customEffect.request(transaction: 32))
        let custom = try USBLightingCommand.customEffect.request(transaction: 1)
        XCTAssertEqual(Array(custom[5..<14]), [6,15,2,0,0,8,0,0,0])
    }

    func testUSBSnapshotRejectsUnrestorableCustomEffectsAndMalformedReplies() throws {
        let effect = try KeyboardEffect(kind: .wave, direction: 2)
        XCTAssertEqual(try USBLightingCommand.decodeEffect(Data([0,0]) + effect.payload), effect)
        XCTAssertThrowsError(try USBLightingCommand.decodeEffect(Data([0,0,8,0,0,0])))
        XCTAssertThrowsError(try USBLightingCommand.decodeEffect(Data([1,0]) + effect.payload))
        XCTAssertThrowsError(try USBLightingCommand.decodeEffect(Data([0,0,4,2,33,0])))
        let command = USBLightingCommand.readEffect
        var packet = try command.request(transaction: 1)
        packet[0] = 2; packet[5] = 6
        packet.replaceSubrange(8..<14, with: [0,0,4,2,40,0])
        packet[88] = packet[2..<88].reduce(0, ^)
        XCTAssertEqual(try command.response(packet, transaction: 1).payload, Data([0,0,4,2,40,0]))
        XCTAssertThrowsError(try command.response(packet, transaction: 2))
        for index in [6,7,88] {
            var corrupt = packet; corrupt[index] ^= 1
            XCTAssertThrowsError(try command.response(corrupt, transaction: 1))
        }
        XCTAssertThrowsError(try command.response(Data(packet.dropLast()), transaction: 1))
        for status: UInt8 in [1,3,5,7] {
            packet[0] = status
            let reply = try command.response(packet, transaction: 1)
            XCTAssertEqual(reply.status, status); XCTAssertTrue(reply.payload.isEmpty)
        }
    }

    func testPresetSuiteOnlyUsesKnownCanonicalEffects() throws {
        XCTAssertEqual(LightingLabPattern.presetSteps.count, 9)
        for (_, effect) in LightingLabPattern.presetSteps {
            XCTAssertNoThrow(try Protocol30Request.keyboardEffect(transaction: 1, effect: effect))
            let usb = try USBLightingCommand.effect(effect).request(transaction: 1)
            XCTAssertEqual(usb[6], 15); XCTAssertEqual(usb[7], 2)
            XCTAssertEqual(Array(usb[8..<10]), [0,0])
            XCTAssertEqual(try USBLightingCommand.decodeEffect(Data([0,0]) + effect.payload), effect)
        }
    }

    func testRecoveryPreservesSnapshotOnWrongDeviceFailedWriteAndWrongReadback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = LightingLabRecovery(url: directory.appendingPathComponent("pending.json"))
        let saved = try KeyboardEffect(kind: .wave, direction: 2)
        try journal.save(LightingLabSnapshot(connection: "usb", identity: "device-one", effect: saved))
        var writes = 0
        for (connection, identity) in [("usb", "device-two"), ("bluetooth", "device-one")] {
            XCTAssertThrowsError(try journal.restore(connection: connection, identity: identity,
                apply: { _ in writes += 1 }, read: { saved }))
            XCTAssertTrue(journal.pending)
        }
        XCTAssertEqual(writes, 0)
        XCTAssertThrowsError(try journal.restore(connection: "usb", identity: "device-one",
            apply: { _ in throw LightingLabError.invalidPacket }, read: { saved }))
        XCTAssertTrue(journal.pending)
        let wrong = try KeyboardEffect(kind: .off)
        XCTAssertThrowsError(try journal.restore(connection: "usb", identity: "device-one",
            apply: { _ in writes += 1 }, read: { wrong }))
        XCTAssertTrue(journal.pending)
        XCTAssertEqual(try journal.load().validatedEffect(), saved)
        try journal.restore(connection: "usb", identity: "device-one", apply: {
            XCTAssertEqual($0, saved); writes += 1
        }, read: { saved })
        XCTAssertFalse(journal.pending)
        XCTAssertEqual(writes, 2)
    }

    func testRecoveryCannotOverwriteARecordOrSaveAnUnrestorableEffect() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = LightingLabRecovery(url: directory.appendingPathComponent("pending.json"))
        let custom = try KeyboardEffect(payload: Data([8,0,0,0]))
        XCTAssertThrowsError(try journal.save(LightingLabSnapshot(connection: "usb", identity: "one", effect: custom)))
        XCTAssertFalse(journal.pending)
        let saved = try KeyboardEffect(kind: .spectrum)
        try journal.save(LightingLabSnapshot(connection: "usb", identity: "one", effect: saved))
        XCTAssertThrowsError(try journal.save(LightingLabSnapshot(connection: "usb", identity: "two", effect: saved)))
        XCTAssertEqual(try journal.load().identity, "one")
        let permissions = try FileManager.default.attributesOfItem(atPath: journal.url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        try Data("not a recovery record".utf8).write(to: journal.url)
        var wrote = false
        XCTAssertThrowsError(try journal.restore(connection: "usb", identity: "one", apply: { _ in wrote = true }, read: { saved }))
        XCTAssertFalse(wrote); XCTAssertTrue(journal.pending)
    }
}
