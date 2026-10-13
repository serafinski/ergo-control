import SwiftUI
import AppKit
import ErgoDevice

final class BluetoothAppDelegate: NSObject, NSApplicationDelegate {
    var controller: BluetoothController?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller?.requestTermination() ?? .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ErgoBluetoothApp: App {
    @NSApplicationDelegateAdaptor(BluetoothAppDelegate.self) var delegate
    @StateObject private var controller = BluetoothController()
    @State private var showDetails = false

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 18) {
                Text("PT Ergo · Bluetooth Mode").font(.largeTitle.bold())
                Text(controller.modeText).font(.title2)
                Text(controller.status).foregroundStyle(.secondary)
                HStack {
                    Button(controller.ready ? "Read Mode Again" : controller.restoreOwed ? "Connect & Restore" : "Connect & Read Mode") {
                        if controller.ready { controller.readMode() } else { controller.connect() }
                    }.disabled(controller.busy)
                    Button("Try Driver Mode for 60 Seconds") { controller.tryDriverMode() }
                        .disabled(!controller.canTryDriverMode)
                }
                HStack {
                    Text(controller.batteryText)
                    Spacer()
                    Button("Read Battery") { controller.readBattery() }
                        .disabled(!controller.ready || controller.busy || controller.restoreOwed)
                }
                if controller.restoreOwed {
                    HStack {
                        Text(controller.secondsRemaining > 0 ? "Restoring in \(controller.secondsRemaining) seconds" : "Restoration pending")
                            .font(.headline.monospacedDigit())
                        Spacer()
                        Button("Restore Now") { controller.restore() }
                    }
                }
                Text("Read the current mode first. A temporary test changes only this PT Ergo, saves its original mode, and restores it automatically. Keep the keyboard connected until restoration is verified. No key mappings, macros, firmware, or drivers are installed.")
                    .font(.callout).foregroundStyle(.secondary)
                DisclosureGroup("Bluetooth diagnostic details", isExpanded: $showDetails) {
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(Array(controller.rows.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.frame(height: 240)
                }
                Button("Show Diagnostic Log") {
                    if let url = controller.logURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }.disabled(controller.logURL == nil)
            }.padding(28).frame(minWidth: 760, minHeight: 360)
                .onAppear { delegate.controller = controller }
        }.windowResizability(.contentMinSize)
    }
}
