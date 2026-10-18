import XCTest
@testable import ErgoCore

final class MusicFallbackTests: XCTestCase {
    func testNativeDefaultAndNextPreviousNeverRequireAnIdleFallback() {
        for running in [true, false] {
            XCTAssertEqual(MusicFallbackDecision.resolve(command: .playPause, preferred: .system, running: running), .system)
            for app in MusicFallbackApplication.allCases {
                for command in [MediaPlaybackCommand.next, .previous] {
                    XCTAssertEqual(MusicFallbackDecision.resolve(command: command, preferred: app, running: running), .system)
                }
            }
        }
    }
    func testExplicitPreferredAppNeverFallsThroughToAStaleSystemTarget() {
        for app in [MusicFallbackApplication.music, .spotify] {
            XCTAssertEqual(MusicFallbackDecision.resolve(command: .playPause, preferred: app, running: false), .open)
            XCTAssertEqual(MusicFallbackDecision.resolve(command: .playPause, preferred: app, running: true), .control)
        }
    }
    func testSavedChoicePreservesLegacyDefaultAndUsesExactApplicationIdentities() {
        XCTAssertEqual(MusicFallbackApplication(savedValue: nil), .system)
        XCTAssertEqual(MusicFallbackApplication(savedValue: "unrecognized"), .system)
        XCTAssertEqual(MusicFallbackApplication(savedValue: "spotify"), .spotify)
        XCTAssertEqual(MusicFallbackApplication.music.bundleID, "com.apple.Music")
        XCTAssertEqual(MusicFallbackApplication.spotify.bundleID, "com.spotify.client")
        XCTAssertNil(MusicFallbackApplication.system.bundleID)
    }
}
