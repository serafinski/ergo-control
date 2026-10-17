import Foundation

public enum InputAccessMode: String {
    case fullKeyboard
    case macroButtons
    public func accepts(reportID: UInt32) -> Bool { self == .fullKeyboard || reportID == 5 }
    public func supports(control: String) -> Bool { self == .fullKeyboard || control.hasPrefix("extra:") }
}

public enum InputCaptureStopReason {
    case keyboardDisconnected, failure
    public init(helperMessage: String) {
        // Exact v1 helper wire reason. Helper/XPC/lease failures must not be
        // mistaken for a sleeping keyboard, even if they say "disconnected".
        self = helperMessage == "PT Ergo disconnected" ? .keyboardDisconnected : .failure
    }
}
