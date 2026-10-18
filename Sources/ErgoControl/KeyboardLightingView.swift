import SwiftUI
import AppKit
import ErgoCore
import ErgoDevice

struct KeyboardLightingView: View {
    @ObservedObject var model: ControlModel
    @State private var kind: KeyboardEffectKind = .static
    @State private var firstColor = Color.green
    @State private var secondColor = Color.blue
    @State private var breathingColors = 1
    @State private var direction: UInt8 = 1

    private var device: BluetoothController { model.bluetooth }
    private let effects = KeyboardEffectKind.allCases
    private var available: Bool { device.canEditKeyboardLighting && !model.preparing }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
        KeyboardPowerView(model: model)
        GroupBox("Keyboard lighting") {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Set the backlight effect for the whole keyboard.").foregroundStyle(.secondary)
                    Spacer()
                    Button(device.ready ? "Read keyboard" : "Connect keyboard") {
                        if device.ready { device.refreshKeyboardLighting() } else { device.connect() }
                    }.disabled(model.preparing || (device.ready ? !available : device.busy || device.keyboardEffectBusy))
                }
                if !device.keyboardEffectIDs.isEmpty {
                    Picker("Effect", selection: $kind) {
                        ForEach(effects) { effect in Text(effect.name).tag(effect) }
                    }
                    if !KeyboardEffectKind.advertised(by: device.keyboardEffectIDs).contains(kind) {
                        Text("This effect wasn’t listed by the keyboard. Apply lighting will check whether it is accepted.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if kind == .breathing {
                        Picker("Colors", selection: $breathingColors) {
                            Text("Random").tag(0)
                            Text("One color").tag(1)
                            Text("Two colors").tag(2)
                        }
                    }
                    if kind == .static || (kind == .breathing && breathingColors > 0) {
                        HStack(spacing: 24) {
                            ColorPicker("Color", selection: $firstColor, supportsOpacity: false)
                            if kind == .breathing && breathingColors == 2 {
                                ColorPicker("Second color", selection: $secondColor, supportsOpacity: false)
                            }
                            Spacer()
                        }
                    }
                    if kind == .wave {
                        Picker("Direction", selection: $direction) {
                            Text("Left").tag(UInt8(1)); Text("Right").tag(UInt8(2))
                        }
                    }
                    Button("Apply lighting") { apply() }
                        .disabled(!available)
                }
                if device.statusLightingActive {
                    Text("Chat status is using the backlight. Controls return after a one-shot wave finishes or selected chats become idle. Pending approval keeps its signal active.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(device.keyboardEffectStatus).font(.callout).textSelection(.enabled)
                Text("Works with mappings on or off. Lighting applies to every profile. Keep keyboard brightness above 0% to see the effect.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }
        }
        .onReceive(device.$currentKeyboardEffect) { effect in
            guard let effect else { return }
            // Readback replaces the draft only on a read/apply result, never on
            // unrelated battery or mapping updates.
            if let readKind = effect.kind { kind = readKind }
            else if let first = effects.first { kind = first }
            if let color = effect.colors.first { firstColor = swiftColor(color) }
            if effect.colors.count > 1 { secondColor = swiftColor(effect.colors[1]) }
            if effect.kind == .breathing { breathingColors = min(2, effect.colors.count) }
            if effect.kind == .wave, effect.flags == 1 || effect.flags == 2 { direction = effect.flags }
        }
    }

    private func apply() {
        var colors: [DialColor] = []
        if kind == .static || (kind == .breathing && breathingColors > 0) { colors.append(rgb(firstColor)) }
        if kind == .breathing && breathingColors == 2 { colors.append(rgb(secondColor)) }
        if let effect = try? KeyboardEffect(kind: kind, colors: colors, direction: direction) {
            device.applyKeyboardEffect(effect)
        }
    }
    private func rgb(_ color: Color) -> DialColor {
        let value = NSColor(color).usingColorSpace(.deviceRGB) ?? .green
        return DialColor(red: UInt8((value.redComponent * 255).rounded()),
                         green: UInt8((value.greenComponent * 255).rounded()),
                         blue: UInt8((value.blueComponent * 255).rounded()))
    }
    private func swiftColor(_ color: DialColor) -> Color {
        Color(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255)
    }
}
