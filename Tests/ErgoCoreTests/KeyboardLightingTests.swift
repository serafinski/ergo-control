import XCTest
@testable import ErgoCore

final class KeyboardLightingTests: XCTestCase {
    func testPhysicalIndicatorWaitsForBacklightThenRetriesOnceAndCancelsOnStop() {
        var gate = DialBacklightGate()
        XCTAssertFalse(gate.mayFlash(rawBrightness: 0))
        XCTAssertFalse(gate.retryAfterBrightnessChange(rawBrightness: 0))
        XCTAssertTrue(gate.retryAfterBrightnessChange(rawBrightness: 1))
        XCTAssertFalse(gate.retryAfterBrightnessChange(rawBrightness: 1))
        XCTAssertTrue(gate.mayFlash(rawBrightness: 127))
        XCTAssertFalse(gate.mayFlash(rawBrightness: 0))
        gate.cancel()
        XCTAssertFalse(gate.retryAfterBrightnessChange(rawBrightness: 127))
    }
    func testLightingPacketsMatchRecoveredProtocolTemplates() throws {
        XCTAssertEqual(try Protocol30Request.readLightingRegions(transaction: 1).header, Data([1,0,0,0,16,128,0,1]))
        XCTAssertEqual(try Protocol30Request.readKeyboardBrightness(transaction: 2, region: 5).header, Data([2,0,0,0,16,133,1,5]))
        XCTAssertEqual(try Protocol30Request.keyboardBrightness(transaction: 3, raw: 127).writeChunks,
                       [Data([3,1,0,0,16,5,1,0]), Data([127])])
        XCTAssertEqual(try Protocol30Request.readDialColor(transaction: 4).header, Data([4,0,0,0,6,132,1,39]))
        // The template/getter use RGB plus brightness; correct the vendor's
        // undersized allocation while preserving a saved brightness on restore.
        XCTAssertEqual(try Protocol30Request.dialColor(transaction: 5, color: .defaultColor(for: "Zoom")).writeChunks,
                       [Data([5,4,0,0,6,4,1,39]), Data([255,0,0,255])])
        XCTAssertEqual(try Protocol30Request.dialColor(transaction: 5, color: .defaultColor(for: "Zoom"), brightness: 42).payload,
                       Data([255,0,0,42]))
        XCTAssertEqual(try Protocol30Request.readDialLightState(transaction: 6).header, Data([6,0,0,0,6,130,1,39]))
        XCTAssertEqual(try Protocol30Request.readLEDClasses(transaction: 8).header, Data([8,0,0,0,6,128,0,0]))
        XCTAssertEqual(try Protocol30Request.readLEDTargets(transaction: 9, ledClass: 1).header, Data([9,0,0,0,6,129,1,0]))
        XCTAssertEqual(try Protocol30Request.dialLightState(transaction: 7, on: true).writeChunks,
                       [Data([7,1,0,0,6,2,1,39]), Data([1])])
    }

    func testBrightnessTurnsPreserveOrderAtBothLimitsAndDuringAnExchange() {
        var queue = BrightnessSteps()
        queue.append(1); queue.append(-1)
        XCTAssertEqual(queue.takeTarget(from: 255), 242) // 100 -> 100 -> 95
        queue.append(-1); queue.append(1)
        XCTAssertEqual(queue.takeTarget(from: 0), 12) // 0 -> 0 -> 5
        queue.append(1)
        let inFlightTarget = queue.takeTarget(from: 127)
        XCTAssertEqual(inFlightTarget, 140) // 50 -> 55
        queue.append(1); queue.append(1)
        XCTAssertEqual(queue.takeTarget(from: inFlightTarget), 165) // 55 -> 65
        XCTAssertTrue(queue.isEmpty)
    }

    func testBrightnessQueueBoundsAndCancellation() {
        var queue = BrightnessSteps()
        XCTAssertFalse(queue.append(0)); XCTAssertFalse(queue.append(10))
        for _ in 0..<256 { XCTAssertTrue(queue.append(1)) }
        XCTAssertFalse(queue.append(1))
        XCTAssertEqual(queue.takeTarget(from: 0), 255)
        queue.append(-1); queue.clear()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.takeTarget(from: 255), 255)
    }

    func testOldProfilesMigrateOnceAndRetainCustomModesAndMappings() throws {
        var original = MappingConfiguration()
        original.profiles[0].dialModes.removeAll { $0.clockwise.kind == .keyboardBrightness }
        original.profiles[0].mappings["extra:32"] = MappingAction(.text, "Keep my mapping")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["schema"] = 1
        var profiles = try XCTUnwrap(json["profiles"] as? [[String: Any]])
        profiles[0]["gamingMode"] = true
        profiles[0]["blockQuit"] = true
        var modes = try XCTUnwrap(profiles[0]["dialModes"] as? [[String: Any]])
        for i in modes.indices { modes[i].removeValue(forKey: "color") }
        profiles[0]["dialModes"] = modes; json["profiles"] = profiles
        let migrated = try JSONDecoder().decode(MappingConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.schema, 2)
        XCTAssertEqual(migrated.profiles[0].mappings, original.profiles[0].mappings)
        XCTAssertEqual(Array(migrated.profiles[0].dialModes.dropLast()), original.profiles[0].dialModes)
        XCTAssertEqual(migrated.profiles[0].dialModes.last?.clockwise.kind, .keyboardBrightness)
        let encoded = try JSONEncoder().encode(migrated)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("gamingMode"))
        XCTAssertEqual(try JSONDecoder().decode(MappingConfiguration.self, from: encoded), migrated)
        var removed = migrated
        removed.profiles[0].dialModes.removeLast()
        XCTAssertEqual(try JSONDecoder().decode(MappingConfiguration.self, from: JSONEncoder().encode(removed)), removed)
    }

    func testCustomColorsRoundTripAndInvalidChannelsFail() throws {
        var mode = DialMode.keyboardBrightness
        mode.color = DialColor(red: 9, green: 23, blue: 182)
        XCTAssertEqual(try JSONDecoder().decode(DialMode.self, from: JSONEncoder().encode(mode)), mode)
        XCTAssertThrowsError(try JSONDecoder().decode(DialColor.self, from: Data(#"{"red":256,"green":0,"blue":0}"#.utf8)))
    }
}
