import Foundation

/// Deliberately bounded experiments, separate from normal mappings/settings.
public enum LightingLabPattern: String, CaseIterable {
    case presets, macroSolid = "macro-solid", macroPulse = "macro-pulse"
    case macroColors = "macro-colors", scan, chase, progress, rainbow

    public var requiresZones: Bool { self != .presets }
    public var explanation: String {
        switch self {
        case .presets: return "Static colors, breathing, spectrum, and Wave in both directions"
        case .macroSolid: return "Only the shared M1–M5 column is cyan"
        case .macroPulse: return "The shared M1–M5 column gently pulses"
        case .macroColors: return "The shared M1–M5 column cycles status colors"
        case .scan: return "One illuminated zone steps through all 19 zones"
        case .chase: return "A moving line with a fading trail across the 19 zones"
        case .progress: return "A progress bar fills the 19 zones"
        case .rainbow: return "A moving rainbow across the 19 zones"
        }
    }

    public func frame(at seconds: Double) throws -> [DialColor] {
        guard requiresZones, seconds.isFinite, seconds >= 0 else { throw LightingLabError.invalidPattern }
        let black = DialColor(red: 0, green: 0, blue: 0)
        let cyan = DialColor(red: 0, green: 180, blue: 255)
        var result = Array(repeating: black, count: 19)
        // Bound time before converting to an integer, including external previews.
        let tick = Int((seconds.truncatingRemainder(dividingBy: 60) * 5).rounded(.down))
        switch self {
        case .presets: throw LightingLabError.invalidPattern
        case .macroSolid: result[0] = cyan
        case .macroPulse:
            let level = (1 - cos(seconds.truncatingRemainder(dividingBy: 2) * .pi)) / 2
            result[0] = DialColor(red: 0, green: UInt8(180 * level), blue: UInt8(255 * level))
        case .macroColors:
            let colors = [DialColor(red: 255, green: 150, blue: 0),
                          DialColor(red: 0, green: 255, blue: 70),
                          DialColor(red: 255, green: 0, blue: 60)]
            result[0] = colors[Int(seconds.truncatingRemainder(dividingBy: 6) / 2)]
        case .scan: result[tick % 19] = cyan
        case .chase:
            for trail in 0..<4 {
                let level = Double(4 - trail) / 4
                result[(tick - trail + 19) % 19] = DialColor(red: 0, green: UInt8(180 * level), blue: UInt8(255 * level))
            }
        case .progress:
            for index in 0..<(tick % 20) { result[index] = cyan }
        case .rainbow:
            for index in 0..<19 {
                let h = (Double(index) / 19 + seconds.truncatingRemainder(dividingBy: 4) / 4)
                    .truncatingRemainder(dividingBy: 1) * 6
                let x = UInt8(255 * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)))
                switch Int(h) {
                case 0: result[index] = DialColor(red: 255, green: x, blue: 0)
                case 1: result[index] = DialColor(red: x, green: 255, blue: 0)
                case 2: result[index] = DialColor(red: 0, green: 255, blue: x)
                case 3: result[index] = DialColor(red: 0, green: x, blue: 255)
                case 4: result[index] = DialColor(red: x, green: 0, blue: 255)
                default: result[index] = DialColor(red: 255, green: 0, blue: x)
                }
            }
        }
        return result
    }

    public static var presetSteps: [(String, KeyboardEffect)] {
        let red = DialColor(red: 255, green: 0, blue: 0)
        let blue = DialColor(red: 0, green: 70, blue: 255)
        let green = DialColor(red: 0, green: 255, blue: 70)
        return [
            ("Static red", try! KeyboardEffect(kind: .static, colors: [red])),
            ("Static green", try! KeyboardEffect(kind: .static, colors: [green])),
            ("Static blue", try! KeyboardEffect(kind: .static, colors: [blue])),
            ("Breathing, one color", try! KeyboardEffect(kind: .breathing, colors: [blue])),
            ("Breathing, two colors", try! KeyboardEffect(kind: .breathing, colors: [red, blue])),
            ("Breathing, random colors", try! KeyboardEffect(kind: .breathing)),
            ("Spectrum cycling", try! KeyboardEffect(kind: .spectrum)),
            ("Wave, left", try! KeyboardEffect(kind: .wave, direction: 1)),
            ("Wave, right", try! KeyboardEffect(kind: .wave, direction: 2))
        ]
    }
}

public enum LightingLabError: LocalizedError {
    case invalidPattern, invalidPacket, unsupportedOriginal, message(String)
    public var errorDescription: String? {
        switch self {
        case .invalidPattern: return "Choose a valid lighting pattern and duration."
        case .invalidPacket: return "Unexpected USB lighting response; test stopped."
        case .unsupportedOriginal: return "The current effect cannot be restored exactly; no test was started. Select a built-in effect first."
        case .message(let text): return text
        }
    }
}

/// USB protocol 2.5, recovered from this model's middleware. Bluetooth uses a
/// different command family. No generic command/address or onboard storage API.
public struct USBLightingCommand {
    public let commandID: UInt8
    private let payload: Data
    private init(_ id: UInt8, _ payload: Data) { commandID = id; self.payload = payload }

    public static var readEffect: Self { Self(0x82, Data(repeating: 0, count: 80)) }
    public static var customEffect: Self { Self(2, Data([0, 0, 8, 0, 0, 0])) }
    public static func effect(_ effect: KeyboardEffect) throws -> Self {
        _ = try Protocol30Request.keyboardEffect(transaction: 1, effect: effect)
        return Self(2, Data([0, 0]) + effect.payload)
    }
    public static func frame(_ colors: [DialColor]) throws -> Self {
        guard colors.count == 19 else { throw LightingLabError.invalidPattern }
        return Self(3, colors.reduce(Data([0, 0, 0, 0, 18])) { $0 + $1.bytes })
    }
    public func request(transaction: UInt8) throws -> Data {
        guard (1...31).contains(transaction) else { throw LightingLabError.invalidPacket }
        var bytes = [UInt8](repeating: 0, count: 90)
        bytes[1] = transaction; bytes[5] = UInt8(payload.count)
        bytes[6] = 15; bytes[7] = commandID
        bytes.replaceSubrange(8..<(8 + payload.count), with: payload)
        bytes[88] = bytes[2..<88].reduce(0, ^)
        return Data(bytes)
    }
    public func response(_ data: Data, transaction: UInt8) throws -> (status: UInt8, payload: Data) {
        let b = Array(data)
        guard b.count == 90, b[1] == transaction, b[6] == 15, b[7] == commandID,
              b[5] <= 80, b[88] == b[2..<88].reduce(0, ^) else { throw LightingLabError.invalidPacket }
        return (b[0], b[0] == 2 ? Data(b[8..<(8 + Int(b[5]))]) : Data())
    }
    public static func decodeEffect(_ payload: Data) throws -> KeyboardEffect {
        let bytes = Array(payload)
        guard bytes.count >= 6, bytes[0] == 0, bytes[1] == 0 else { throw LightingLabError.invalidPacket }
        let effect = try KeyboardEffect(payload: Data(bytes.dropFirst(2)))
        // Custom frames cannot be reconstructed from an effect selector alone.
        guard (try? Self.effect(effect)) != nil else { throw LightingLabError.unsupportedOriginal }
        return effect
    }
}
