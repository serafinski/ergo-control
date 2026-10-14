import Foundation

/// The USB-only knob getter templates recovered from rzDevice25.
/// This codec deliberately cannot encode a setter or choose another address.
public enum USBKnobRead: CaseIterable {
    case currentMode, configuration, indicatorState, indicatorRGB

    public var commandID: UInt8 {
        switch self {
        case .currentMode: return 0x93
        case .configuration: return 0x92
        case .indicatorState: return 0x80
        case .indicatorRGB: return 0x81
        }
    }
    public var payloadSize: Int {
        switch self {
        case .currentMode: return 8
        case .configuration: return 50
        case .indicatorState: return 3
        case .indicatorRGB: return 5
        }
    }

    public func request(transaction: UInt8) throws -> Data {
        guard (1...31).contains(transaction) else { throw USBKnobReadError.invalidTransaction }
        var bytes = [UInt8](repeating: 0, count: 90)
        bytes[1] = transaction
        bytes[5] = UInt8(payloadSize)
        bytes[6] = 3; bytes[7] = commandID
        bytes[8] = 1; bytes[9] = 39
        bytes[88] = bytes[2..<88].reduce(0, ^)
        return Data(bytes)
    }

    public func response(_ data: Data, transaction: UInt8) throws -> USBKnobReadResponse {
        let bytes = Array(data)
        guard bytes.count == 90, bytes[1] == transaction,
              bytes[6] == 3, bytes[7] == commandID,
              bytes[88] == bytes[2..<88].reduce(0, ^), bytes[5] <= 80 else {
            throw USBKnobReadError.invalidResponse
        }
        guard bytes[0] == 2 else { return USBKnobReadResponse(status: bytes[0], payload: Data()) }
        guard Int(bytes[5]) == payloadSize, bytes[8] == 1, bytes[9] == 39 else {
            throw USBKnobReadError.invalidResponse
        }
        return USBKnobReadResponse(status: 2, payload: Data(bytes[8..<(8 + payloadSize)]))
    }
}

public struct USBKnobReadResponse {
    public let status: UInt8
    public let payload: Data
}

public enum USBKnobReadError: Error {
    case invalidTransaction, invalidResponse
}
