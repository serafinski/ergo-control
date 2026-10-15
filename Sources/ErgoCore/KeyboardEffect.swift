import Foundation

/// New Chroma IDs used by protocol 3.0, distinct from the legacy LED matrix IDs.
public enum KeyboardEffectKind: UInt8, CaseIterable, Identifiable {
    case off = 0, `static` = 1, breathing = 2, spectrum = 3, wave = 4
    public var id: UInt8 { rawValue }
    public var name: String {
        switch self {
        case .off: return "Off"
        case .static: return "Static"
        case .breathing: return "Breathing"
        case .spectrum: return "Spectrum cycling"
        case .wave: return "Wave"
        }
    }
    public static func advertised(by ids: [UInt8]) -> [Self] {
        allCases.filter { ids.contains($0.rawValue) }
    }
}

public enum KeyboardLightingRequest: Equatable {
    case read
    case apply(KeyboardEffect)
}

/// A user click waits for the shared configuration channel instead of being
/// dropped or disabling the UI every time a background check starts.
public struct KeyboardLightingRequests {
    private var pending: KeyboardLightingRequest?
    public init() {}
    public var isEmpty: Bool { pending == nil }
    @discardableResult public mutating func enqueue(_ request: KeyboardLightingRequest) -> Bool {
        guard pending == nil else { return false }
        pending = request
        return true
    }
    public mutating func takeIfIdle(commandBusy: Bool, dialLightingBusy: Bool) -> KeyboardLightingRequest? {
        guard !commandBusy, !dialLightingBusy else { return nil }
        let request = pending
        pending = nil
        return request
    }
    public mutating func cancel() { pending = nil }
}

public struct KeyboardEffect: Equatable {
    public let id: UInt8
    public let flags: UInt8
    public let rate: UInt8
    public let colors: [DialColor]
    public var kind: KeyboardEffectKind? { KeyboardEffectKind(rawValue: id) }

    public init(kind: KeyboardEffectKind, colors: [DialColor] = [], direction: UInt8 = 1) throws {
        let valid: Bool
        switch kind {
        case .static: valid = colors.count == 1
        case .breathing: valid = colors.count <= 2
        case .wave: valid = colors.isEmpty && (direction == 1 || direction == 2)
        case .off, .spectrum: valid = colors.isEmpty
        }
        guard valid else { throw KeyboardEffectError.invalidSettings }
        id = kind.rawValue
        flags = kind == .breathing ? UInt8(colors.count) : kind == .wave ? direction : 0
        rate = kind == .wave ? 40 : 0
        self.colors = colors
    }

    /// Preserve unfamiliar effects when reading; only the five understood effects
    /// above can be constructed for writing. Firmware may pad the response.
    public init(payload: Data) throws {
        let bytes = Array(payload)
        guard bytes.count >= 4, bytes[3] <= 2, bytes.count >= 4 + Int(bytes[3]) * 3 else {
            throw KeyboardEffectError.invalidResponse
        }
        id = bytes[0]; flags = bytes[1]; rate = bytes[2]
        colors = (0..<Int(bytes[3])).map { index in
            let offset = 4 + index * 3
            return DialColor(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2])
        }
    }
    public var payload: Data {
        colors.reduce(Data([id, flags, rate, UInt8(colors.count)])) { $0 + $1.bytes }
    }
}

public enum KeyboardEffectError: LocalizedError {
    case invalidSettings, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .invalidSettings: return "Choose valid colors and a direction for this effect."
        case .invalidResponse: return "The keyboard returned an unexpected lighting effect."
        }
    }
}

public extension Protocol30Request {
    static func readKeyboardEffectIDs(transaction: UInt8) throws -> Self {
        try Self(transaction: transaction, commandClass: 16, commandID: 0x82)
    }
    static func readKeyboardEffect(transaction: UInt8) throws -> Self {
        try Self(transaction: transaction, commandClass: 16, commandID: 0x83, argument6: 1)
    }
    static func keyboardEffect(transaction: UInt8, effect: KeyboardEffect) throws -> Self {
        // Live device setting: profile 1, AllRegion (0), matching the vendor task.
        guard let kind = effect.kind else { throw KeyboardEffectError.invalidSettings }
        let validated = try KeyboardEffect(kind: kind, colors: effect.colors, direction: effect.flags)
        guard effect == validated else { throw KeyboardEffectError.invalidSettings }
        return try Self(transaction: transaction, commandClass: 16, commandID: 3, argument6: 1, payload: effect.payload)
    }
}
