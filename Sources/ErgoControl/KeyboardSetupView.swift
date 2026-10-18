import SwiftUI
import AppKit
import ApplicationServices
import IOKit.hid
import ErgoCore

struct KeyboardSetupView: View {
    @ObservedObject var model: ControlModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Setup & diagnostics").font(.largeTitle.bold())
            Text("Keyboard access, connection checks and troubleshooting.").foregroundStyle(.secondary)
            GroupBox("Keyboard connection") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.status).textSelection(.enabled)
                    Text(model.bluetooth.batteryText).foregroundStyle(.secondary)
                    if model.bluetooth.restoreOwed && !model.running {
                        Text(model.bluetooth.status).font(.callout).textSelection(.enabled)
                    }
                    if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    if model.inputAccessMode == .macroButtons {
                        Text("Only macro buttons are available. Full keyboard control is needed for custom dials, media buttons and ordinary key mappings.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("macOS permissions") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Input Monitoring reads the keyboard. Accessibility lets mappings type text and shortcuts.")
                        .font(.callout).foregroundStyle(.secondary)
                    permission("Input Monitoring", granted: model.inputGranted, url: "Privacy_ListenEvent")
                    permission("Accessibility", granted: model.accessibilityGranted, url: "Privacy_Accessibility")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("Full keyboard control") {
                VStack(alignment: .leading, spacing: 14) {
                    Text(model.fullControlHelper.status).textSelection(.enabled)
                    Text("The input helper is required to replace dial actions and ordinary keys. It needs its own Input Monitoring permission. Installation asks for administrator approval.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        if model.fullControlHelper.needsStartupRepair {
                            Button("Repair helper startup…") { model.enableFullControl() }
                        } else if model.fullControlHelper.needsApproval {
                            Button("Open approval settings") { model.fullControlHelper.showApproval() }
                        } else if !model.fullControlHelper.enabled {
                            Button(model.fullControlHelper.usesLocalCertificate ? "Install input helper…" : "Enable full keyboard control…") {
                                model.enableFullControl()
                            }
                        }
                        Button("Refresh helper status") { model.fullControlHelper.refresh() }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("Media controls") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Prefer focused window for playback (experimental)", isOn: $model.focusedMediaPlayback)
                    Text("With a preferred music app selected under Keyboard → Buttons, Play / pause follows the focused player, then that app. On also remembers the last media window and routes track navigation there. macOS default with this off keeps system playback. Volume and mute always use system media keys.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("App logs show media controls received from the keyboard and events posted to macOS. Posted events do not confirm that a player handled them.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            DisclosureGroup("Advanced input checks") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("A temporary test enables your saved mappings for 60 seconds, then restores the keyboard.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Start 60-second mapping test") { model.start(testSeconds: 60) }
                        .disabled(model.running || model.preparing || model.waitingForAutomaticStart)
                    Button("Check helper permission") { model.fullControlHelper.checkPermission() }
                        .disabled(!model.fullControlHelper.enabled || model.fullControlHelper.checkingPermission || model.running || model.preparing)
                    Text("Stop mappings before checking the helper’s permission.").font(.caption).foregroundStyle(.secondary)
                    if !model.bluetooth.lightingStatus.isEmpty {
                        Text(model.bluetooth.lightingStatus).font(.callout).textSelection(.enabled)
                    }
                    Text("Last control: \(model.lastControl)").font(.caption).foregroundStyle(.secondary)
                    if model.fullControlHelper.enabled {
                        Divider()
                        Button("Remove input helper…", role: .destructive) { model.removeFullControl() }
                    }
                }.padding(.top, 8)
            }
            Text("For recent errors and connection events, open App logs in the sidebar.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func permission(_ title: String, granted: Bool, url: String) -> some View {
        Button {
            if !granted {
                if url == "Privacy_ListenEvent" { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
                if url == "Privacy_Accessibility" {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                }
            }
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(url)")!)
        } label: {
            Label(title + (granted ? " · Ready" : " · Required"), systemImage: granted ? "checkmark.circle.fill" : "circle")
        }
    }
}
