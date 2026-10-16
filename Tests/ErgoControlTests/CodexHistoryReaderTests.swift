import XCTest
import ErgoCore
@testable import ErgoControl

final class CodexHistoryReaderTests: XCTestCase {
    func testClosedDesktopDoesNotLaunchMetadataProcessOrDisableSavedConnection() throws {
        var launches = 0
        let reader = CodexHistoryReader(desktopApp: { nil }, launch: { _ in launches += 1 })
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bridge = CodexBridge(folder: folder, startTimer: false, history: reader)
        defer { bridge.shutdown() }
        bridge.setEnabled(true)
        bridge.refreshHistory()
        XCTAssertEqual(launches, 0)
        XCTAssertTrue(bridge.settings.enabled)
        XCTAssertTrue(bridge.historyMessage.contains("Codex is closed"))
        XCTAssertTrue(bridge.displaySlots.allSatisfy { $0.threadID == nil })
        bridge.setSelection(.fixed)
        bridge.assign(0, name: "Saved chat", link: UUID().uuidString)
        XCTAssertEqual(bridge.displaySlots[0].name, "Saved chat")
    }

    func testSlowLaunchAndCancellationLeaveMainRunLoopResponsive() {
        let launched = expectation(description: "Launch runs off main")
        let heartbeat = expectation(description: "Main remains responsive during launch")
        let release = DispatchSemaphore(value: 0)
        let connection = CodexHistoryConnection(executable: URL(fileURLWithPath: "/bin/cat"), launch: { _ in
            XCTAssertFalse(Thread.isMainThread)
            launched.fulfill()
            _ = release.wait(timeout: .now() + 3)
        })
        connection.onData = { _ in XCTFail("Cancelled connection delivered data") }
        connection.onFailure = { _ in XCTFail("Cancelled connection delivered an error") }
        connection.start()
        wait(for: [launched], timeout: 2)
        DispatchQueue.main.async {
            connection.stop()
            heartbeat.fulfill()
            release.signal()
        }
        wait(for: [heartbeat], timeout: 1)
    }

    func testHistoryReconnectsWhenDesktopOpensAndStopsWhenItCloses() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let executable = app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A local fixture speaks only the metadata handshake/list sequence. It
        // never touches the installed Codex app, authentication or saved chats.
        let script = """
        #!/bin/sh
        read -r line
        echo '{"id":1,"result":{}}'
        read -r line
        case "$line" in *initialized*) ;; *) exit 1 ;; esac
        read -r line
        echo '{"id":2,"result":{"data":[],"nextCursor":null}}'
        read -r line
        echo '{"id":3,"result":{"data":[]}}'
        while read -r line; do :; done
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        defer { try? FileManager.default.removeItem(at: app) }
        var running: URL?
        let reader = CodexHistoryReader(desktopApp: { running })
        defer { reader.stop() }
        var offline = 0
        reader.onProblem = { issue in
            if case .unavailable(let message) = issue, message.contains("Codex is closed") { offline += 1 }
            else { XCTFail("Unexpected metadata failure") }
        }
        reader.refresh()
        XCTAssertEqual(offline, 1)
        let synced = expectation(description: "Metadata sync completes after desktop opens")
        reader.onPinned = { slots in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(slots.count, 5)
            synced.fulfill()
        }
        running = app; reader.refresh()
        wait(for: [synced], timeout: 3)
        running = nil; reader.refresh()
        XCTAssertEqual(offline, 2)
    }
}
