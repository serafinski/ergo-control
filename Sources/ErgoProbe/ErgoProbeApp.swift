import SwiftUI
import AppKit
import ErgoCore

final class Session: ObservableObject {
    let log = CaptureLog()
    let hid: HIDProbe
    let bluetooth: BluetoothProbe

    init() {
        hid = HIDProbe(log: log)
        bluetooth = BluetoothProbe(log: log)
    }

    func stop() { hid.stop(); bluetooth.stop(); log.end() }
}

struct ProbeView: View {
    @ObservedObject var log: CaptureLog
    @ObservedObject var hid: HIDProbe
    @ObservedObject var bluetooth: BluetoothProbe
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PT Ergo · Input Discovery").font(.largeTitle.bold())
            Text("Capture the missing controls over Bluetooth before assigning actions.")
                .foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label(hid.status, systemImage: hid.running ? "keyboard.fill" : "keyboard")
                    Label(bluetooth.status, systemImage: "antenna.radiowaves.left.and.right")
                    HStack {
                        Button("Start Keyboard Capture") { hid.start() }.disabled(hid.running)
                        Button("Observe Bluetooth") { bluetooth.start(identifiers: hid.peripheralIDs()) }
                            .disabled(bluetooth.running)
                        Button("Stop & Save") { session.stop() }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            Text("1. Start capture.  2. Choose a control.  3. Mark the test, then operate that control three times.")
            HStack {
                Picker("Control", selection: $log.step) {
                    ForEach(CaptureStep.allCases) { step in Text(step.rawValue).tag(step) }
                }
                Button("Mark Test") { log.mark() }.disabled(!hid.running && !bluetooth.running)
            }
            Text("Only PT Ergo (068e:02c3) is opened. Capture keeps normal input working and sends no keyboard configuration commands. Ordinary PT Ergo keys are recorded while capture is active.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(log.rows.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(8)
            }.background(.background.secondary).clipShape(RoundedRectangle(cornerRadius: 8))
            if let failure = log.failure { Text(failure).foregroundStyle(.red) }
            HStack {
                Text(log.fileURL?.lastPathComponent ?? "No capture file yet").font(.caption)
                Spacer()
                Button("Show Capture File") {
                    if let url = log.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }.disabled(log.fileURL == nil)
                Button("Input Monitoring Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }
            }
        }.padding(24).frame(minWidth: 860, minHeight: 640)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var session: Session?
    func applicationWillTerminate(_ notification: Notification) { session?.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ErgoProbeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var session = Session()

    init() {
        if CommandLine.arguments.contains("--inventory") {
            let probe = HIDProbe(log: CaptureLog())
            let result: [String: Any] = ["devices": probe.inventory(),
                "matchedPeripheralCount": probe.peripheralIDs().count]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data + Data([10]))
            }
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup {
            ProbeView(log: session.log, hid: session.hid, bluetooth: session.bluetooth, session: session)
                .onAppear { delegate.session = session }
        }.windowResizability(.contentMinSize)
    }
}
