import SwiftUI
import AppKit
import ErgoCore

struct FunctionKeySettingsView: View {
    @ObservedObject var model: ControlModel
    private let modifierChoices = [("rightoption", "Right Option (default)"), ("leftoption", "Left Option"),
        ("rightcontrol", "Right Control"), ("leftcontrol", "Left Control"),
        ("rightshift", "Right Shift"), ("leftshift", "Left Shift"),
        ("rightcommand", "Right Command"), ("leftcommand", "Left Command")]
    private var shortcutChoice: Binding<String> {
        Binding(get: {
            let value = model.configuration.functionKeys.fluidVoiceShortcut
            return modifierChoices.contains { $0.0 == value } ? value : "custom"
        }, set: { choice in
            model.configuration.functionKeys.fluidVoiceShortcut = choice == "custom" ? "ctrl+shift+space" : choice
        })
    }
    var body: some View {
        GroupBox("Search and dictation") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("F4 · Search", selection: $model.configuration.functionKeys.search) {
                    ForEach(SearchKeyProvider.allCases) { Text($0.label).tag($0) }
                }
                Picker("F5 · Dictation", selection: $model.configuration.functionKeys.dictation) {
                    ForEach(DictationKeyProvider.allCases) { Text($0.label).tag($0) }
                }
                if model.configuration.functionKeys.dictation == .fluidVoice {
                    Picker("Fluid Voice shortcut", selection: shortcutChoice) {
                        ForEach(modifierChoices, id: \.0) { Text($0.1).tag($0.0) }
                        Text("Custom shortcut…").tag("custom")
                    }
                    if shortcutChoice.wrappedValue == "custom" {
                        TextField("Shortcut", text: $model.configuration.functionKeys.fluidVoiceShortcut,
                                  prompt: Text("Example: ctrl+shift+space"))
                    }
                    Text("Choose the same dictation shortcut in Fluid Voice and keep it running. F5 follows your press and release, supporting Fluid Voice’s toggle or hold mode.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Fluid Voice") { openFluidVoice() }
                }
                Text("Applies to all profiles. Your custom F4/F5 mappings take priority. Use Save changes to keep these choices.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }
    private func openFluidVoice() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.FluidApp.app") else {
            model.error = "Fluid Voice is not installed. Choose Apple dictation or install Fluid Voice first."; return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error { DispatchQueue.main.async { model.error = error.localizedDescription } }
        }
    }
}
