import Foundation

public enum ActionKind: String, CaseIterable, Codable, Identifiable {
    case standard = "Default", shortcut = "Shortcut", macro = "Macro", text = "Type text"
    case application = "Open application", script = "Run script", scroll = "Scroll"
    case toggleApplication = "Show / minimize application"
    case media = "Media action", cycleDial = "Next dial mode", layer = "Hold alternate layer"
    case keyboardBrightness = "Keyboard brightness"
    case codexChat = "Open Codex chat slot"
    case battery = "Show battery", disabled = "Do nothing"
    public var id: String { rawValue }
    public var label: String { self == .codexChat ? "Open chat slot" : rawValue }
}

public struct MappingAction: Codable, Equatable {
    public var kind: ActionKind
    public var value: String
    public init(_ kind: ActionKind = .standard, _ value: String = "") { self.kind = kind; self.value = value }
}

public struct DialMode: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var clockwise: MappingAction
    public var counterclockwise: MappingAction
    public var color: DialColor
    public init(name: String, clockwise: MappingAction, counterclockwise: MappingAction, color: DialColor? = nil) {
        id = UUID(); self.name = name; enabled = true
        self.clockwise = clockwise; self.counterclockwise = counterclockwise
        self.color = color ?? .defaultColor(for: name)
    }
    private enum CodingKeys: String, CodingKey { case id, name, enabled, clockwise, counterclockwise, color }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        clockwise = try values.decode(MappingAction.self, forKey: .clockwise)
        counterclockwise = try values.decode(MappingAction.self, forKey: .counterclockwise)
        color = try values.decodeIfPresent(DialColor.self, forKey: .color) ?? .defaultColor(for: name)
    }
    public static var keyboardBrightness: Self {
        Self(name: "Keyboard brightness", clockwise: MappingAction(.keyboardBrightness, "up"),
             counterclockwise: MappingAction(.keyboardBrightness, "down"))
    }
}

public struct MappingProfile: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var applicationIDs: [String]
    public var mappings: [String: MappingAction]
    public var alternate: [String: MappingAction]
    public var dialModes: [DialMode]
    public init(name: String = "Default") {
        id = UUID(); self.name = name; applicationIDs = []; mappings = [:]; alternate = [:]
        dialModes = [
            .keyboardBrightness,
            DialMode(name: "Zoom", clockwise: MappingAction(.shortcut, "cmd+keypadplus"), counterclockwise: MappingAction(.shortcut, "cmd+keypadminus")),
            DialMode(name: "Scroll", clockwise: MappingAction(.scroll, "down"), counterclockwise: MappingAction(.scroll, "up")),
            DialMode(name: "Switch applications", clockwise: MappingAction(.shortcut, "cmd+tab"), counterclockwise: MappingAction(.shortcut, "cmd+shift+tab")),
            DialMode(name: "Browser tabs", clockwise: MappingAction(.shortcut, "ctrl+tab"), counterclockwise: MappingAction(.shortcut, "ctrl+shift+tab"))
        ]
    }
}

public struct MappingConfiguration: Codable, Equatable {
    public var schema = 2
    public var profiles: [MappingProfile]
    public var manualProfileID: UUID
    public var autoSwitch = true
    public var functionKeys = FunctionKeyPreferences()
    public init() { let profile = MappingProfile(); profiles = [profile]; manualProfileID = profile.id }
    private enum CodingKeys: String, CodingKey { case schema, profiles, manualProfileID, autoSwitch, functionKeys }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schema = try values.decode(Int.self, forKey: .schema)
        profiles = try values.decode([MappingProfile].self, forKey: .profiles)
        manualProfileID = try values.decode(UUID.self, forKey: .manualProfileID)
        autoSwitch = try values.decode(Bool.self, forKey: .autoSwitch)
        // Pre-selector builds used Raycast. Preserve that behavior on upgrade;
        // brand-new configurations use the system providers instead.
        functionKeys = try values.decodeIfPresent(FunctionKeyPreferences.self, forKey: .functionKeys)
            ?? FunctionKeyPreferences(search: .raycast)
        if schema == 1 {
            for index in profiles.indices {
                if !profiles[index].dialModes.contains(where: {
                    $0.clockwise.kind == .keyboardBrightness || $0.counterclockwise.kind == .keyboardBrightness
                }) { profiles[index].dialModes.append(.keyboardBrightness) }
            }
            schema = 2
        }
    }
    public func profile(for applicationID: String?) -> MappingProfile {
        if autoSwitch, let applicationID,
           let profile = profiles.first(where: { $0.applicationIDs.contains(applicationID) }) { return profile }
        return profiles.first(where: { $0.id == manualProfileID }) ?? profiles.first ?? MappingProfile()
    }
}

public struct KeyChord: Equatable {
    public let usage: UInt8
    public let modifiers: UInt8
    public init(_ text: String) throws {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.last, let usage = Self.names[key] else { throw MappingValidationError.message("Choose a supported key, such as cmd+c, ctrl+tab, or shift+f5") }
        var modifiers: UInt8 = 0
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command": modifiers |= 8
            case "shift": modifiers |= 2
            case "ctrl", "control": modifiers |= 1
            case "alt", "option": modifiers |= 4
            default: throw MappingValidationError.message("Unknown modifier: \(part)")
            }
        }
        self.usage = usage; self.modifiers = modifiers
    }
    public static let names: [String: UInt8] = {
        var result: [String: UInt8] = [:]
        for (i, char) in "abcdefghijklmnopqrstuvwxyz".enumerated() { result[String(char)] = UInt8(i + 4) }
        for (i, char) in "1234567890".enumerated() { result[String(char)] = UInt8(i + 30) }
        let keys: [String: UInt8] = ["return":40,"enter":40,"escape":41,"delete":42,"tab":43,"space":44,
            "minus":45,"equal":46,"leftbracket":47,"rightbracket":48,"backslash":49,"semicolon":51,
            "quote":52,"grave":53,"comma":54,"period":55,"slash":56,"capslock":57,
            "home":74,"pageup":75,"forwarddelete":76,"end":77,"pagedown":78,"right":79,"left":80,"down":81,"up":82,
            "keypadplus":87,"keypadminus":86,"keypadenter":88]
        result.merge(keys) { a, _ in a }
        for i in 1...12 { result["f\(i)"] = UInt8(57 + i) }
        for i in 13...20 { result["f\(i)"] = UInt8(104 + i - 13) }
        return result
    }()
}

public enum MacroStep: Equatable {
    case chord(KeyChord), delay(Int), text(String)
    public static func parse(_ source: String) throws -> [MacroStep] {
        var result: [MacroStep] = []; var duration = 0
        for raw in source.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("wait ") {
                guard let ms = Int(line.dropFirst(5)), (0...10_000).contains(ms) else { throw MappingValidationError.message("Wait must be between 0 and 10000 milliseconds") }
                duration += ms; result.append(.delay(ms))
            } else if line.hasPrefix("text ") { result.append(.text(String(line.dropFirst(5)))) }
            else { result.append(.chord(try KeyChord(line))) }
        }
        guard !result.isEmpty, result.count <= 200, duration <= 60_000 else { throw MappingValidationError.message("Use 1–200 macro steps, with at most 60 seconds of waits") }
        return result
    }
}

public enum MappingValidationError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

public enum ControlCatalog {
    public static let controls: [(String, String)] = [
        ("leftCW", "Left dial · clockwise"), ("leftCCW", "Left dial · counterclockwise"), ("extra:96", "Left dial · click"),
        ("rightCW", "Right roller · clockwise"), ("rightCCW", "Right roller · counterclockwise"), ("rightClick", "Right roller · click"),
        ("extra:32", "M1"), ("extra:33", "M2"), ("extra:34", "M3"), ("extra:35", "M4"), ("extra:36", "M5"),
        ("extra:247", "AI button"), ("mediaSingle", "Media · single press"), ("mediaDouble", "Media · double press"),
        ("mediaTriple", "Media · triple press"), ("extra:65", "Battery button"),
        ("extra:253", "Right space"), ("extra:252", "Split B · extra key"), ("extra:251", "Split Backspace · extra key")]
    public static func label(_ id: String) -> String {
        if let label = controls.first(where: { $0.0 == id })?.1 { return label }
        if id.hasPrefix("key:"), let value = UInt8(id.dropFirst(4)),
           let name = KeyChord.names.filter({ $0.value == value }).map(\.key).sorted().first { return name.uppercased() }
        return id
    }
}
