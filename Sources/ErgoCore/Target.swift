import Foundation

public enum ErgoTarget {
    public static let vendorID = 0x068e
    public static let productID = 0x02c3
    public static let transport = "Bluetooth Low Energy"
    public static let service = "52401523-F97C-7F90-0E7F-6C6F4E36DB1C"
    public static let notify = "52401525-F97C-7F90-0E7F-6C6F4E36DB1C"

    public static func matches(vendor: Int, product: Int, transport: String) -> Bool {
        vendor == vendorID && product == productID && transport == self.transport
    }
}

public enum CaptureStep: String, CaseIterable, Identifiable {
    case baseline = "Baseline — hands off keyboard"
    case ordinary = "Ordinary key — press A once"
    case leftClockwise = "Left dial — clockwise"
    case leftCounterclockwise = "Left dial — counterclockwise"
    case leftClick = "Left dial — click"
    case leftShiftClick = "Left dial — Shift + click"
    case rightClockwise = "Right roller — clockwise"
    case rightCounterclockwise = "Right roller — counterclockwise"
    case rightClick = "Right roller — click"
    case m1 = "M1"
    case m2 = "M2"
    case m3 = "M3"
    case m4 = "M4"
    case m5 = "M5"
    case ai = "AI button"
    case media = "Media — single press"
    case mediaDouble = "Media — double press"
    case mediaTriple = "Media — triple press"
    case battery = "Battery button"
    public var id: String { rawValue }
}
