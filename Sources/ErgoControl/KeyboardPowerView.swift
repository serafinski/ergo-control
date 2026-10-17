import SwiftUI
import ErgoCore
import ErgoDevice

struct KeyboardPowerView: View {
    @ObservedObject var model: ControlModel
    @State private var brightnessEnabled = true
    @State private var brightness = 5.0
    @State private var dimEnabled = true
    @State private var dimSeconds: UInt16 = 300
    @State private var sleepEnabled = true
    @State private var sleepSeconds: UInt16 = 900
    @AppStorage("lastKeyboardBrightness") private var lastBrightness = 5
    private var device: BluetoothController { model.bluetooth }
    private var available: Bool { device.ready && !model.preparing && !device.powerSettingsBusy && !device.powerTestRecoveryPending }
    private var changes: KeyboardPowerChanges {
        guard let observed = device.powerSettings else { return KeyboardPowerChanges() }
        let changeBrightness = brightnessEnabled != (observed.brightness > 0) || (brightnessEnabled && Int(brightness) != observed.brightnessPercent)
        let dim = KeyboardDimming(enabled: dimEnabled, seconds: dimSeconds, percentage: observed.dimming.percentage)
        let sleep = KeyboardSleep(enabled: sleepEnabled, seconds: sleepSeconds)
        return KeyboardPowerChanges(brightness: changeBrightness ? (brightnessEnabled ? UInt8(Int(brightness) * 255 / 100) : 0) : nil,
                                    dimming: dim == observed.dimming ? nil : dim, sleep: sleep == observed.sleep ? nil : sleep)
    }
    private var dirty: Bool { changes.brightness != nil || changes.dimming != nil || changes.sleep != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            GroupBox("Brightness & battery power") {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("Settings stored on your keyboard.").foregroundStyle(.secondary)
                        Spacer()
                        Button(device.ready ? "Read power settings" : "Connect keyboard") {
                            if device.ready { device.refreshPowerSettings() } else { device.connect() }
                        }.disabled(model.preparing || (device.ready && device.powerSettingsBusy))
                    }
                    if device.powerSettings != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Keyboard lighting", isOn: $brightnessEnabled).disabled(!available)
                            HStack(spacing: 16) {
                                Text("Brightness").frame(width: 90, alignment: .leading)
                                Slider(value: $brightness, in: 1...100, step: 1) { Text("Brightness") }
                                    .labelsHidden()
                                Text("\(Int(brightness))%")
                                    .monospacedDigit().frame(width: 45, alignment: .trailing)
                            }
                            .frame(maxWidth: 700)
                            .disabled(!brightnessEnabled || !available)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Dim lighting when running on battery", isOn: $dimEnabled).disabled(!available)
                            timerPicker("Dim after", seconds: $dimSeconds).disabled(!dimEnabled || !available)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Wireless sleep when running on battery", isOn: $sleepEnabled).disabled(!available)
                            timerPicker("Sleep after", seconds: $sleepSeconds).disabled(!sleepEnabled || !available)
                        }
                        Text("Dimming keeps the keyboard’s existing dim level. Wireless sleep may pause mappings and status lights until the keyboard wakes.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Apply keyboard settings") {
                            if brightnessEnabled { lastBrightness = max(1, Int(brightness)) }
                            device.applyPowerSettings(changes)
                        }.buttonStyle(.borderedProminent).disabled(!available || !dirty)
                    }
                    Text(device.powerSettingsMessage).font(.callout).textSelection(.enabled)
                    if device.lightingSuppressed {
                        Label("Lighting is temporarily off. Activity or display wake restores your brightness.", systemImage: "moon")
                            .font(.callout)
                    }
                }.padding(16)
                .disabled(model.preparing)
            }
            LightingOffView(automation: model.lightingAutomation)
        }
        .onAppear { load(device.powerSettings); if device.ready && device.powerSettings == nil { device.refreshPowerSettings() } }
        .onChange(of: device.ready) { _, ready in if ready && device.powerSettings == nil { device.refreshPowerSettings() } }
        .onChange(of: device.powerSettings) { _, settings in load(settings) }
        .onChange(of: dimEnabled) { _, enabled in if enabled && !(60...900).contains(dimSeconds) { dimSeconds = 300 } }
        .onChange(of: sleepEnabled) { _, enabled in if enabled && !(60...3600).contains(sleepSeconds) { sleepSeconds = 900 } }
    }
    private func timerPicker(_ title: String, seconds: Binding<UInt16>) -> some View {
        HStack(spacing: 16) {
            Text(title).frame(width: 90, alignment: .leading)
            Picker(title, selection: seconds) {
                ForEach(Array(Set([UInt16(60),180,300,600,900,seconds.wrappedValue])).sorted(), id: \.self) { value in
                    Text(value == 0 ? "Not set" : value % 60 == 0 ? "\(value / 60) min" : "\(value) sec").tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 180)
        }
    }

    private func load(_ value: KeyboardPowerSettings?) {
        guard let value else { return }
        brightnessEnabled = value.brightness > 0
        brightness = Double(value.brightness > 0 ? value.brightnessPercent : max(1, min(100, lastBrightness)))
        if value.brightness > 0 { lastBrightness = value.brightnessPercent }
        dimEnabled = value.dimming.enabled; dimSeconds = value.dimming.seconds
        sleepEnabled = value.sleep.enabled; sleepSeconds = value.sleep.seconds
    }
}

private struct LightingOffView: View {
    @ObservedObject var automation: LightingAutomation
    var body: some View {
        GroupBox("Switch off lighting") {
            VStack(alignment: .leading, spacing: 20) {
                Toggle("When the display is turned off", isOn: $automation.preferences.whenDisplaySleeps)
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("When idle", isOn: $automation.preferences.whenIdle)
                    Stepper("After \(automation.preferences.idleMinutes) min", value: $automation.preferences.idleMinutes, in: 1...15)
                        .disabled(!automation.preferences.whenIdle)
                }
                Text("Applies while Ergo Control is running. Keyboard, mouse or trackpad activity restores your brightness. These switches also turn off Chat status lights; leave them off to keep status visible while you’re away.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Saved automatically on this Mac.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
    }
}
