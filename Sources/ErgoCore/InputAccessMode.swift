import Foundation

public enum InputAccessMode: String {
    case fullKeyboard
    case macroButtons
    public func accepts(reportID: UInt32) -> Bool { self == .fullKeyboard || reportID == 5 }
    public func supports(control: String) -> Bool { self == .fullKeyboard || control.hasPrefix("extra:") }
}
