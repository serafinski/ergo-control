import XCTest
@testable import ErgoCore

final class MusicFallbackTests: XCTestCase {
    func testNativeDefaultAndNextPreviousNeverRequireAnIdleFallback() {
        for target in [MediaTargetAvailability.available, .none, .unknown] {
            XCTAssertEqual(MusicFallbackDecision.resolve(command: .playPause, preferred: .system, target: target), .system)
            for app in MusicFallbackApplication.allCases {
                for command in [MediaPlaybackCommand.next, .previous] {
                    XCTAssertEqual(MusicFallbackDecision.resolve(command: command, preferred: app, target: target), .system)
                }
            }
        }
    }
    func testExistingPlayerAlwaysOwnsPlayPauseAndUnknownDoesNotLaunchAnything() {
        for app in [MusicFallbackApplication.music, .spotify] {
            XCTAssertEqual(MusicFallbackDecision.resolve(command: .playPause, preferred: app, target: .available), .system)
            XCTAssertEqual(MusicFallbackDecision.resolve(command: .playPause, preferred: app, target: .none), .open(app))
            XCTAssertEqual(MusicFallbackDecision.resolve(command: .playPause, preferred: app, target: .unknown), .unavailable)
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
