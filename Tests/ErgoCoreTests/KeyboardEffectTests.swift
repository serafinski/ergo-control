import XCTest
@testable import ErgoCore

final class KeyboardEffectTests: XCTestCase {
    private let green = DialColor(red: 0, green: 255, blue: 0)
    private let blue = DialColor(red: 0, green: 0, blue: 255)

    func testNewChromaTemplatesUseDistinctIDsAndLiveStorage() throws {
        XCTAssertEqual(try Protocol30Request.readKeyboardEffectIDs(transaction: 1).header, Data([1,0,0,0,16,130,0,0]))
        XCTAssertEqual(try Protocol30Request.readKeyboardEffect(transaction: 2).header, Data([2,0,0,0,16,131,1,0]))
        let effect = try KeyboardEffect(kind: .breathing, colors: [green, blue])
        XCTAssertEqual(try Protocol30Request.keyboardEffect(transaction: 3, effect: effect).writeChunks,
                       [Data([3,10,0,0,16,3,1,0]), Data([2,2,0,2,0,255,0,0,0,255])])
        XCTAssertEqual(try KeyboardEffect(kind: .static, colors: [green]).payload, Data([1,0,0,1,0,255,0]))
        XCTAssertEqual(try KeyboardEffect(kind: .wave, direction: 2).payload, Data([4,2,40,0]))
        XCTAssertEqual(try KeyboardEffect(kind: .spectrum).payload, Data([3,0,0,0]))
        XCTAssertEqual(try KeyboardEffect(kind: .off).payload, Data([0,0,0,0]))
        XCTAssertEqual(try KeyboardEffect(kind: .breathing).payload, Data([2,0,0,0]))
    }
    func testColorsAndDirectionsAreValidatedBeforeWriting() throws {
        XCTAssertThrowsError(try KeyboardEffect(kind: .static))
        XCTAssertThrowsError(try KeyboardEffect(kind: .breathing, colors: [green, green, blue]))
        XCTAssertThrowsError(try KeyboardEffect(kind: .spectrum, colors: [green]))
        XCTAssertThrowsError(try KeyboardEffect(kind: .wave, direction: 0))
        XCTAssertThrowsError(try KeyboardEffect(kind: .off, colors: [green]))
        // A received custom-frame or unknown payload must never become a write.
        let unknown = try KeyboardEffect(payload: Data([8,0,0,0]))
        XCTAssertThrowsError(try Protocol30Request.keyboardEffect(transaction: 1, effect: unknown))
        let badFlags = try KeyboardEffect(payload: Data([2,7,0,1,0,255,0]))
        XCTAssertThrowsError(try Protocol30Request.keyboardEffect(transaction: 1, effect: badFlags))
    }
    func testReadbackPreservesFlagsColorsAndAcceptsPaddingButRejectsTruncation() throws {
        let effect = try KeyboardEffect(kind: .breathing, colors: [green, blue])
        XCTAssertEqual(try KeyboardEffect(payload: effect.payload), effect)
        XCTAssertEqual(try KeyboardEffect(payload: effect.payload + Data([0,0])), effect)
        for bytes: [UInt8] in [[], [2], [2,1,0], [2,1,0,1,0,255], [2,2,0,2,0,255,0], [2,0,0,255]] {
            XCTAssertThrowsError(try KeyboardEffect(payload: Data(bytes)))
        }
    }
    func testAdvertisedMetadataRecognizesOnlyImplementedEffects() {
        XCTAssertEqual(KeyboardEffectKind.advertised(by: [1,2,8,99]), [.static, .breathing])
        XCTAssertEqual(KeyboardEffectKind.advertised(by: []), [])
        XCTAssertEqual(KeyboardEffectKind.advertised(by: [4,2,0,3,1]), KeyboardEffectKind.allCases)
    }
    func testLightingClickWaitsAcrossBackgroundChecksAndRunsOnlyOnce() throws {
        var requests = KeyboardLightingRequests()
        let apply = KeyboardLightingRequest.apply(try KeyboardEffect(kind: .breathing))
        XCTAssertTrue(requests.enqueue(apply))
        XCTAssertFalse(requests.enqueue(.read))
        XCTAssertNil(requests.takeIfIdle(commandBusy: true, dialLightingBusy: false))
        XCTAssertNil(requests.takeIfIdle(commandBusy: false, dialLightingBusy: true))
        XCTAssertFalse(requests.isEmpty)
        XCTAssertEqual(requests.takeIfIdle(commandBusy: false, dialLightingBusy: false), apply)
        XCTAssertNil(requests.takeIfIdle(commandBusy: false, dialLightingBusy: false))
        XCTAssertTrue(requests.isEmpty)
    }
    func testRestorationCancelsAQueuedLightingReadOrWrite() throws {
        for request in [KeyboardLightingRequest.read, .apply(try KeyboardEffect(kind: .wave))] {
            var requests = KeyboardLightingRequests()
            XCTAssertTrue(requests.enqueue(request))
            requests.cancel()
            XCTAssertTrue(requests.isEmpty)
            XCTAssertNil(requests.takeIfIdle(commandBusy: false, dialLightingBusy: false))
        }
    }
}
