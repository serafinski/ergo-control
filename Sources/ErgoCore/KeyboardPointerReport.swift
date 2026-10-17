import Foundation

/// PT Ergo report 2, as declared by its HID descriptor: five buttons, constant
/// padding, signed horizontal pan/wheel, then signed 16-bit relative X/Y.
/// Horizontal pan drives the left dial; vertical wheel drives the right roller.
/// Report-5 clicks own mode switching/mute; button/movement fields are auxiliary.
public struct KeyboardPointerReport {
    public let buttons: UInt8
    public let horizontalPan: Int
    public let verticalWheel: Int
    public let deltaX: Int
    public let deltaY: Int
    public var hasAuxiliaryInput: Bool { buttons != 0 || deltaX != 0 || deltaY != 0 }
    public init?(_ data: Data) {
        let bytes = Array(data)
        guard bytes.count == 9, bytes[0] == 2 else { return nil }
        buttons = bytes[1] & 0x1f
        horizontalPan = Int(Int8(bitPattern: bytes[3]))
        verticalWheel = Int(Int8(bitPattern: bytes[4]))
        deltaX = Int(Int16(bitPattern: UInt16(bytes[5]) | UInt16(bytes[6]) << 8))
        deltaY = Int(Int16(bitPattern: UInt16(bytes[7]) | UInt16(bytes[8]) << 8))
    }
}
