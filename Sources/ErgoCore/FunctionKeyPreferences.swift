import Foundation

public enum SearchKeyProvider: String, Codable, CaseIterable, Identifiable {
    case spotlight, raycast
    public var id: String { rawValue }
    public var label: String { self == .spotlight ? "Spotlight" : "Raycast" }
}

public enum DictationKeyProvider: String, Codable, CaseIterable, Identifiable {
    case apple, fluidVoice
    public var id: String { rawValue }
    public var label: String { self == .apple ? "Apple dictation" : "Fluid Voice" }
}

public struct FunctionKeyPreferences: Codable, Equatable {
    public var search: SearchKeyProvider
    public var dictation: DictationKeyProvider
    public var fluidVoiceShortcut: String
    public init(search: SearchKeyProvider = .spotlight, dictation: DictationKeyProvider = .apple,
                fluidVoiceShortcut: String = "rightoption") {
        self.search = search; self.dictation = dictation; self.fluidVoiceShortcut = fluidVoiceShortcut
    }
}

/// A modifier tap/hold or a modified key chord, not a recording API or app launcher.
public struct DictationTrigger: Equatable {
    public let modifiers: UInt8
    public let usage: UInt8?
    public init(_ text: String) throws {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let modifierNames: [String: UInt8] = ["leftcontrol":1,"leftshift":2,"leftoption":4,"leftcommand":8,
                                             "rightcontrol":16,"rightshift":32,"rightoption":64,"rightcommand":128]
        if let modifier = modifierNames[name] { modifiers = modifier; usage = nil; return }
        let chord = try KeyChord(name)
        guard chord.modifiers != 0 || (58...69).contains(chord.usage) || (104...111).contains(chord.usage) else {
            throw MappingValidationError.message("Use rightoption, another sided modifier, or a shortcut such as ctrl+shift+space.")
        }
        modifiers = chord.modifiers; usage = chord.usage
    }
}
