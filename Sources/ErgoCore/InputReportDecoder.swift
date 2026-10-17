import Foundation

/// Presentation of confirmed PT Ergo inputs. Unknown packets remain raw.
public struct InputReportDecoder {
    private var extraKeys = ExtraKeyDecoder()
    private var consumer: UInt16 = 0
    public init() {}

    public mutating func describe(reportID: UInt32, hexadecimal: String) -> [String]? {
        guard hexadecimal.count == 24 || hexadecimal.count == 18 else { return nil }
        var bytes: [UInt8] = []
        for offset in stride(from: 0, to: hexadecimal.count, by: 2) {
            let start = hexadecimal.index(hexadecimal.startIndex, offsetBy: offset)
            let end = hexadecimal.index(start, offsetBy: 2)
            guard let byte = UInt8(hexadecimal[start..<end], radix: 16) else { return nil }
            bytes.append(byte)
        }
        guard bytes[0] == reportID else { return nil }
        // Confirmed nine-byte report 2: left dial uses signed horizontal pan.
        if reportID == 2, bytes.count == 9, bytes[1] == 0, bytes[2] == 0,
           bytes.dropFirst(4).allSatisfy({ $0 == 0 }), bytes[3] != 0 {
            let steps = Int(Int8(bitPattern: bytes[3]))
            let direction = steps > 0 ? "clockwise" : "counterclockwise"
            return ["Left dial · \(direction)" + (abs(steps) == 1 ? "" : " · \(abs(steps)) steps")]
        }
        if let events = extraKeys.decode(reportID: reportID, bytes: Data(bytes)) {
            return events.map { "\($0.name) · \($0.pressed ? "pressed" : "released")" }
        }
        if reportID == 3, bytes.count == 12, bytes.dropFirst(3).allSatisfy({ $0 == 0 }) {
            let usage = UInt16(bytes[1]) | UInt16(bytes[2]) << 8
            guard usage != consumer else { return [] }
            var events: [String] = []
            if consumer != 0 { events.append("\(Self.consumerName(consumer)) · released") }
            if usage != 0 { events.append("\(Self.consumerName(usage)) · pressed") }
            consumer = usage
            return events
        }
        if let record = DriverMediaRecord(Data(bytes)) {
            return record.usage == 0 ? [] : ["\(Self.consumerName(record.usage)) · driver media event"]
        }
        // Physical report 6, logical notification record 5, brightness event 8.
        if reportID == 6, bytes.count == 12, bytes[1] == 5, bytes[2] == 8,
           bytes.dropFirst(4).allSatisfy({ $0 == 0 }) {
            let percent = Int((Double(bytes[3]) * 100 / 255).rounded())
            return ["Keyboard brightness · \(percent)%"]
        }
        return nil
    }

    private static func consumerName(_ usage: UInt16) -> String {
        switch usage {
        case 0xe9: return "Volume up"
        case 0xea: return "Volume down"
        case 0xe2: return "Mute"
        case 0xcd: return "Play / pause"
        case 0xb5: return "Next track"
        case 0xb6: return "Previous track"
        default: return "Media control \(usage)"
        }
    }
}
