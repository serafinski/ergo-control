import SwiftUI
import AppKit
import ErgoCore

struct TestResult: Codable {
    let control: CaptureStep
    let fileURL: URL
    let savedAt: Date
    let rows: [String]
    let events: [String]
    let reports: Int
    let notifications: Int

    func refreshingDecodedEvents() -> TestResult {
        // Re-label saved recordings after decoder updates without changing the raw evidence.
        guard fileURL.deletingLastPathComponent().standardizedFileURL == CaptureLog.captureDirectory.standardizedFileURL,
              let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 2_000_000,
              let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return self }
        var decoder = InputReportDecoder()
        var decoded: [String] = []
        var count = 0
        for line in text.split(separator: "\n") {
            guard let value = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return self }
            guard value["kind"] as? String == "hid_report" else { continue }
            count += 1
            guard let id = value["reportID"] as? NSNumber, let hex = value["hex"] as? String,
                  let events = decoder.describe(reportID: id.uint32Value, hexadecimal: hex) else { return self }
            decoded.append(contentsOf: events)
        }
        guard count == reports, count > 0, notifications == 0 else { return self }
        return TestResult(control: control, fileURL: fileURL, savedAt: savedAt, rows: rows,
                          events: Array(decoded.suffix(250)), reports: reports, notifications: notifications)
    }
}

final class Session: ObservableObject {
    let log = CaptureLog()
    let hid: HIDProbe
    let bluetooth: BluetoothProbe
    @Published var selection: CaptureStep = .ordinary
    @Published private(set) var activeStep: CaptureStep?
    @Published private(set) var results: [CaptureStep: TestResult] = [:]
    @Published var message: String?
    @Published var observeBluetooth = false

    private var indexURL: URL { CaptureLog.captureDirectory.appendingPathComponent("tests-index.json") }

    init() {
        hid = HIDProbe(log: log)
        bluetooth = BluetoothProbe(log: log)
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([TestResult].self, from: data) {
            for result in saved { results[result.control] = result.refreshingDecodedEvents() }
        }
    }

    func startTest() {
        guard activeStep == nil else { return }
        message = nil
        log.step = selection
        do { try log.begin() } catch { message = error.localizedDescription; return }
        log.record("test_start", ["control": selection.fileKey])
        log.mark()
        hid.start()
        guard hid.running else {
            log.record("test_failed", ["reason": hid.status])
            log.end()
            message = hid.status
            return
        }
        activeStep = selection
        if observeBluetooth { bluetooth.start(identifiers: hid.peripheralIDs()) }
    }

    func finishTest() {
        guard let control = activeStep else { return }
        hid.stop(); bluetooth.stop()
        log.record("test_end", ["control": control.fileKey, "reports": log.reportCount,
                                "notifications": log.notificationCount])
        log.end()
        if let fileURL = log.fileURL {
            results[control] = TestResult(control: control, fileURL: fileURL, savedAt: Date(),
                rows: log.rows, events: log.eventRows, reports: log.reportCount, notifications: log.notificationCount)
            saveIndex()
        }
        activeStep = nil
        message = "Saved \(control.rawValue). Select another control, or start again to retry."
    }

    func clearTest() {
        if activeStep != nil {
            hid.stop(); bluetooth.stop()
            log.record("test_discarded", ["control": selection.fileKey])
            log.end()
            activeStep = nil
        }
        results.removeValue(forKey: selection)
        saveIndex()
        log.resetView()
        message = "\(selection.rawValue) cleared. Start Test creates a fresh recording."
    }

    private func saveIndex() {
        do {
            try FileManager.default.createDirectory(at: CaptureLog.captureDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let saved = CaptureStep.allCases.compactMap { results[$0] }
            try JSONEncoder().encode(saved).write(to: indexURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
        } catch { message = "Test saved, but the test list could not be updated: \(error.localizedDescription)" }
    }

    func stop() {
        if activeStep != nil { finishTest() }
        else { hid.stop(); bluetooth.stop(); log.end() }
    }
}

struct ProbeView: View {
    @ObservedObject var session: Session
    @ObservedObject var log: CaptureLog
    @ObservedObject var hid: HIDProbe
    @ObservedObject var bluetooth: BluetoothProbe
    @State private var showRaw = false
    @State private var showConnection = false

    private var live: Bool { session.activeStep == session.selection }
    private var result: TestResult? { session.results[session.selection] }
    private var rows: [String] { live ? log.rows : result?.rows ?? [] }
    private var events: [String] { live ? log.eventRows : result?.events ?? [] }
    private var count: Int { live ? log.reportCount : result?.reports ?? 0 }
    private var fileURL: URL? { live ? log.fileURL : result?.fileURL }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("PT Ergo").font(.title2.bold()).padding(.horizontal, 16)
                Text("CONTROL TESTS").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(CaptureStep.allCases) { control in
                            Button {
                                session.selection = control
                                session.message = nil
                            } label: {
                                HStack {
                                    Text(control.rawValue + (control == .leftShiftClick ? " (optional)" : ""))
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 4)
                                    if session.activeStep == control {
                                        Image(systemName: "record.circle.fill").foregroundStyle(.red)
                                    } else if let saved = session.results[control] {
                                        Text("\(saved.reports)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                }.padding(.horizontal, 12).padding(.vertical, 9)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(session.selection == control ? Color.accentColor.opacity(0.15) : .clear,
                                                in: RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain)
                                .disabled(session.activeStep != nil && session.activeStep != control)
                        }
                    }.padding(.horizontal, 8)
                }
                Text("\(session.results.count) of \(CaptureStep.allCases.count) controls tested")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
            }.padding(.vertical, 20).frame(width: 280).background(.background.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                Text(session.selection.rawValue).font(.largeTitle.bold())
                Text(live ? "Test running. Operate only this control three times, then finish the test."
                     : "Start the test, operate this control three times, then finish. Its log stays in this section.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    if live {
                        Button("Finish Test") { session.finishTest() }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Start Test") { session.startTest() }.buttonStyle(.borderedProminent)
                    }
                    Button("Clear Test") { session.clearTest() }
                        .disabled(!live && result == nil && !(log.step == session.selection && log.fileURL != nil))
                    Spacer()
                    if live { Label("Recording", systemImage: "record.circle.fill").foregroundStyle(.red) }
                    else if result != nil { Label("Saved", systemImage: "checkmark.circle").foregroundStyle(.green) }
                }
                HStack {
                    Text("\(count) keyboard reports").font(.headline.monospacedDigit())
                    Spacer()
                    if let result, !live { Text(result.savedAt, style: .time).font(.caption).foregroundStyle(.secondary) }
                }
                ScrollView {
                    if events.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: live ? "waveform" : "keyboard").font(.largeTitle).foregroundStyle(.secondary)
                            Text(live ? "Waiting for input from this control…" : result == nil ? "No test recorded for this control" : "No input reports received in this test")
                                .foregroundStyle(.secondary)
                            if !live && result != nil {
                                Text("An empty test does not prove this control is unsupported.").font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, 60)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                                Text(event).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.padding(16)
                    }
                }.frame(minHeight: 160).background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                DisclosureGroup("Raw report details", isExpanded: $showRaw) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.frame(height: 150)
                }
                if let message = session.message { Text(message).font(.callout).foregroundStyle(.secondary) }
                if let failure = log.failure { Text(failure).foregroundStyle(.red) }
                DisclosureGroup("Connection options", isExpanded: $showConnection) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Also observe Bluetooth configuration notifications", isOn: $session.observeBluetooth)
                            .disabled(live)
                        Text(hid.status).font(.caption).foregroundStyle(.secondary)
                        if session.observeBluetooth { Text(bluetooth.status).font(.caption).foregroundStyle(.secondary) }
                        Button("Input Monitoring Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                        }
                    }.padding(.top, 8)
                }
                HStack {
                    Button("Show This Test's File") {
                        if let fileURL { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
                    }.disabled(fileURL == nil)
                    Spacer()
                    Button("Show All Recordings") { NSWorkspace.shared.open(CaptureLog.captureDirectory) }
                }
                Text("Each control has its own recording. Clear resets this section; earlier files stay on your Mac. Only PT Ergo is captured while a test runs, including any ordinary keys you press.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(26).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(minWidth: 980, minHeight: 740)
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
            ProbeView(session: session, log: session.log, hid: session.hid, bluetooth: session.bluetooth)
                .onAppear { delegate.session = session }
        }.windowResizability(.contentMinSize)
    }
}
