import Foundation
import XCTest
@testable import ErgoCore

final class Protocol30Tests: XCTestCase {
    func testQueuedFrameWritesKeepTransportCompletionSeparateFromKeyboardSuccess() throws {
        let request = try BluetoothLightingLabCommand.frame(Array(repeating: .defaultColor(for: "Zoom"), count: 19))
            .request(transaction: 4, region: 5)
        var exchange = try Protocol30Exchange(request: request, queueWrites: true)
        var queued: [Data] = []
        while let chunk = exchange.nextWrite() { queued.append(chunk) }
        XCTAssertEqual(queued, request.writeChunks)
        XCTAssertEqual(queued.count, 5)
        for _ in 0..<4 { try exchange.acknowledgeWrite(); XCTAssertFalse(exchange.writesComplete) }
        try exchange.acknowledgeWrite()
        XCTAssertTrue(exchange.writesComplete)
        XCTAssertNil(exchange.completedResponse, "ATT acknowledgements are not keyboard command success")
        try exchange.receive(header())
        XCTAssertTrue(try XCTUnwrap(exchange.completedResponse).succeeded)
        XCTAssertThrowsError(try exchange.acknowledgeWrite())
    }
    func testEarlyRejectedQueuedFrameCannotCompleteBeforeEveryWriteAcknowledgement() throws {
        let request = try Protocol30Request(transaction: 4, commandClass: 16, commandID: 4, payload: Data(repeating: 0, count: 62))
        var exchange = try Protocol30Exchange(request: request, queueWrites: true)
        while exchange.nextWrite() != nil {}
        try exchange.receive(header(status: 7))
        for _ in 0..<4 { try exchange.acknowledgeWrite(); XCTAssertNil(exchange.completedResponse) }
        try exchange.acknowledgeWrite()
        XCTAssertEqual(exchange.completedResponse?.status, 7)
    }
    private func header(transaction: UInt8 = 4, length: Int = 0, status: UInt8 = 2, size: Int = 20) -> Data {
        Data([transaction, UInt8(length & 255), UInt8((length >> 8) & 255), UInt8((length >> 16) & 255),
              0, 0, 0, status] + Array(repeating: 0, count: size - 8))
    }

    func testModeRequestMatchesHistoricalSuccessfulCommand() throws {
        let request = try Protocol30Request.deviceMode(transaction: 4, mode: 3, parameter: 0)
        XCTAssertEqual(request.header + request.payload, Data([4, 2, 0, 0, 1, 2, 0, 0, 3, 0]))
        XCTAssertEqual(request.writeChunks, [Data([4, 2, 0, 0, 1, 2, 0, 0]), Data([3, 0])])
    }

    func testReadQueriesUseRecoveredClassIDsAndBatteryArgument() throws {
        XCTAssertEqual(try Protocol30Request.readDeviceMode(transaction: 1).writeChunks,
                       [Data([1, 0, 0, 0, 1, 0x82, 0, 0])])
        XCTAssertEqual(try Protocol30Request.readBatteryList(transaction: 2).header,
                       Data([2, 0, 0, 0, 5, 0x80, 0, 1]))
        XCTAssertEqual(try Protocol30Request.readBatteryLevel(transaction: 3, batteryID: 7).header,
                       Data([3, 0, 0, 0, 5, 0x81, 0, 7]))
    }

    func testChunkBoundariesAndLengthEncoding() throws {
        for count in [0, 1, 19, 20, 21, 40, 41, 256, 65536] {
            let data = Data((0..<count).map { UInt8($0 & 255) })
            let request = try Protocol30Request(transaction: 1, commandClass: 0, commandID: 0, payload: data)
            XCTAssertEqual(request.writeChunks.first?.count, 8)
            XCTAssertTrue(request.writeChunks.dropFirst().allSatisfy { $0.count <= 20 })
            XCTAssertEqual(request.writeChunks.dropFirst().reduce(Data(), +), data)
            XCTAssertEqual(Int(request.header[1]) | (Int(request.header[2]) << 8) | (Int(request.header[3]) << 16), count)
        }
    }

    func testTransactionsWrapAndRejectReservedZero() throws {
        var sequence = TransactionSequence()
        let actual: [UInt8] = (0..<64).map { _ in sequence.next() }
        let cycle: [UInt8] = (1...31).map { UInt8($0) }
        let expected: [UInt8] = cycle + cycle + [1, 2]
        XCTAssertEqual(actual, expected)
        for id: UInt8 in [0, 32, 255] {
            XCTAssertThrowsError(try Protocol30Request.readDeviceMode(transaction: id))
            XCTAssertThrowsError(try Protocol30ResponseAssembler(transaction: id))
        }
    }

    func testUnrelatedResponseDoesNotConsumeOurTransaction() throws {
        var assembler = try Protocol30ResponseAssembler(transaction: 4)
        XCTAssertNil(try assembler.append(header(transaction: 3)))
        XCTAssertTrue(try XCTUnwrap(assembler.append(header())).succeeded)
    }

    func testHistoricalZeroLengthModeAcknowledgement() throws {
        var assembler = try Protocol30ResponseAssembler(transaction: 4)
        let response = try XCTUnwrap(assembler.append(header()))
        XCTAssertEqual(response.status, 2)
        XCTAssertTrue(response.payload.isEmpty)
        XCTAssertThrowsError(try assembler.append(header()))
    }

    func testRejectedLightingResponseWaitsForAllWriteAcknowledgements() throws {
        let request = try Protocol30Request.dialColor(transaction: 4, color: .defaultColor(for: "Zoom"))
        var exchange = try Protocol30Exchange(request: request)
        XCTAssertEqual(exchange.nextWrite(), request.header)
        try exchange.receive(header(status: 7))
        XCTAssertNil(exchange.completedResponse)
        try exchange.acknowledgeWrite()
        XCTAssertEqual(exchange.nextWrite(), request.payload)
        XCTAssertNil(exchange.completedResponse)
        try exchange.acknowledgeWrite()
        XCTAssertEqual(exchange.completedResponse?.status, 7)
        XCTAssertEqual(exchange.completedResponse?.succeeded, false)
        XCTAssertNil(exchange.nextWrite())
    }

    func testPayloadFragmentsAreNotMistakenForHeaders() throws {
        var assembler = try Protocol30ResponseAssembler(transaction: 4)
        XCTAssertNil(try assembler.append(header(length: 45)))
        let first = Data([4, 0, 0, 0, 0, 0, 0, 2] + Array(repeating: 9, count: 12))
        XCTAssertNil(try assembler.append(first))
        XCTAssertNil(try assembler.append(Data(repeating: 8, count: 20)))
        let response = try XCTUnwrap(assembler.append(Data(repeating: 7, count: 20)))
        XCTAssertEqual(response.payload, first + Data(repeating: 8, count: 20) + Data(repeating: 7, count: 5))
    }

    func testEightByteHeaderVariantAndFailureStatus() throws {
        var assembler = try Protocol30ResponseAssembler(transaction: 4)
        XCTAssertNil(try assembler.append(header(length: 2, size: 8)))
        XCTAssertEqual(try assembler.append(Data([3, 0]))?.payload, Data([3, 0]))
        var failed = try Protocol30ResponseAssembler(transaction: 4)
        let response = try XCTUnwrap(failed.append(header(status: 7)))
        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.status, 7)
    }

    func testMalformedAndUnboundedHeadersFail() throws {
        var assembler = try Protocol30ResponseAssembler(transaction: 4)
        XCTAssertThrowsError(try assembler.append(Data([4, 2])))
        var bounded = try Protocol30ResponseAssembler(transaction: 4)
        XCTAssertThrowsError(try bounded.append(header(length: 4097)))
    }

    func testActualKeyboardFailureThenSuccessSequence() throws {
        var assembler = try Protocol30ResponseAssembler(transaction: 1)
        // First live mode query: failure, successful header, padded payload.
        XCTAssertNil(try assembler.append(header(transaction: 1, status: 3)))
        XCTAssertNil(try assembler.append(header(transaction: 1, length: 2)))
        let response = try XCTUnwrap(assembler.append(Data(repeating: 0, count: 20)))
        XCTAssertEqual(response.payload, Data([0, 0]))
    }

    func testHeaderAndPayloadWritesMustBeAcknowledgedBeforeCompletion() throws {
        let request = try Protocol30Request.deviceMode(transaction: 4, mode: 3, parameter: 0)
        var exchange = try Protocol30Exchange(request: request)
        XCTAssertEqual(exchange.nextWrite(), request.header)
        XCTAssertNil(exchange.nextWrite())
        try exchange.receive(header())
        XCTAssertNil(exchange.completedResponse)
        try exchange.acknowledgeWrite()
        XCTAssertNil(exchange.completedResponse)
        XCTAssertEqual(exchange.nextWrite(), Data([3, 0]))
        XCTAssertNil(exchange.nextWrite())
        XCTAssertNil(exchange.completedResponse)
        try exchange.acknowledgeWrite()
        XCTAssertTrue(try XCTUnwrap(exchange.completedResponse).succeeded)
        XCTAssertThrowsError(try exchange.acknowledgeWrite())
    }

    func testReadResponseMayArriveBeforeWriteAcknowledgement() throws {
        let request = try Protocol30Request.readDeviceMode(transaction: 4)
        var exchange = try Protocol30Exchange(request: request)
        XCTAssertNotNil(exchange.nextWrite())
        try exchange.receive(header(length: 2))
        try exchange.receive(Data([0, 0]))
        XCTAssertNil(exchange.completedResponse)
        try exchange.acknowledgeWrite()
        XCTAssertEqual(exchange.completedResponse?.payload, Data([0, 0]))
    }
}
