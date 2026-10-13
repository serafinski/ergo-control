import Foundation

// Recovered from rzDevice30 and the Electron Protocol 30 transport.
// This codec has no I/O. Encoding a request does not send it to the keyboard.
public enum Protocol30Error: Error, Equatable {
    case invalidTransaction
    case payloadTooLarge
    case malformedHeader
    case responseTooLarge
    case alreadyCompleted
}

public struct TransactionSequence {
    private var current: UInt8 = 0
    public init() {}
    public mutating func next() -> UInt8 {
        current = current == 31 ? 1 : current + 1
        return current
    }
}

public struct Protocol30Request: Equatable {
    public let transaction: UInt8
    public let header: Data
    public let payload: Data

    public init(transaction: UInt8, commandClass: UInt8, commandID: UInt8,
                argument6: UInt8 = 0, argument7: UInt8 = 0, payload: Data = Data()) throws {
        guard (1...31).contains(transaction) else { throw Protocol30Error.invalidTransaction }
        guard payload.count <= 0x00ff_ffff else { throw Protocol30Error.payloadTooLarge }
        self.transaction = transaction
        self.payload = payload
        let length = payload.count
        header = Data([transaction, UInt8(length & 255), UInt8((length >> 8) & 255),
                       UInt8((length >> 16) & 255), commandClass, commandID, argument6, argument7])
    }

    // The eight-byte header is always a separate characteristic write.
    public var writeChunks: [Data] {
        [header] + stride(from: 0, to: payload.count, by: 20).map {
            Data(payload.dropFirst($0).prefix(20))
        }
    }

    public static func readDeviceMode(transaction: UInt8) throws -> Self {
        try Self(transaction: transaction, commandClass: 1, commandID: 0x82)
    }

    public static func readBatteryList(transaction: UInt8) throws -> Self {
        try Self(transaction: transaction, commandClass: 5, commandID: 0x80, argument7: 1)
    }

    public static func readBatteryLevel(transaction: UInt8, batteryID: UInt8) throws -> Self {
        try Self(transaction: transaction, commandClass: 5, commandID: 0x81, argument7: batteryID)
    }

    // Kept as an offline builder until baseline capture and restoration are implemented.
    public static func deviceMode(transaction: UInt8, mode: UInt8, parameter: UInt8) throws -> Self {
        try Self(transaction: transaction, commandClass: 1, commandID: 2, payload: Data([mode, parameter]))
    }
}

public struct Protocol30Response: Equatable {
    public let transaction: UInt8
    public let status: UInt8
    public let header: Data
    public let payload: Data
    public var succeeded: Bool { status == 2 }
}

/// One outstanding command, a header notification, then payload notifications.
/// Payload fragments do not contain transaction IDs. Do not use this as a general
/// Bluetooth event parser or run multiple commands against the same characteristic.
public struct Protocol30ResponseAssembler {
    private let transaction: UInt8
    private let maximumResponse: Int
    private var header: Data?
    private var expected = 0
    private var payload = Data()
    private var completed = false

    public init(transaction: UInt8, maximumResponse: Int = 4096) throws {
        guard (1...31).contains(transaction) else { throw Protocol30Error.invalidTransaction }
        self.transaction = transaction
        self.maximumResponse = max(0, maximumResponse)
    }

    public mutating func append(_ notification: Data) throws -> Protocol30Response? {
        guard !completed else { throw Protocol30Error.alreadyCompleted }
        let bytes = Array(notification)
        if let header {
            let remaining = expected - payload.count
            payload.append(contentsOf: notification.prefix(remaining))
            guard payload.count == expected else { return nil }
            completed = true
            return Protocol30Response(transaction: transaction, status: 2, header: header, payload: payload)
        }
        // Ignore unrelated responses until our header arrives.
        guard bytes.first == transaction else { return nil }
        // Vendor's unpacker accepts either the normal 20-byte header or an 8-byte variant.
        guard bytes.count == 20 || bytes.count == 8 else { throw Protocol30Error.malformedHeader }
        let status = bytes[7]
        if status != 2 {
            completed = true
            return Protocol30Response(transaction: transaction, status: status, header: notification, payload: Data())
        }
        expected = Int(bytes[1]) | (Int(bytes[2]) << 8) | (Int(bytes[3]) << 16)
        guard expected <= maximumResponse else { throw Protocol30Error.responseTooLarge }
        header = notification
        if expected == 0 {
            completed = true
            return Protocol30Response(transaction: transaction, status: status, header: notification, payload: Data())
        }
        return nil
    }
}
