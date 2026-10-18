import XCTest
@testable import ErgoCore

final class MusicPlaybackDispatchTests: XCTestCase {
    func testFocusedBrowserGetsPlayPauseBeforeAnExplicitIdleMusicApp() {
        for browser in ["com.vivaldi.Vivaldi", "com.apple.Safari", "com.google.Chrome"] {
            XCTAssertEqual(MusicPlaybackDispatch.resolve(command: .playPause, preferred: .spotify,
                focusFirst: false, foregroundBundleID: browser), .focused)
        }
        XCTAssertEqual(MusicPlaybackDispatch.resolve(command: .playPause, preferred: .music,
            focusFirst: false, foregroundBundleID: "com.vivaldi.Vivaldi"), .focused)
    }
    func testPreferredAppKeepsItsNativeMenuAndTrackNavigationKeepsFallbackRouting() {
        XCTAssertEqual(MusicPlaybackDispatch.resolve(command: .playPause, preferred: .spotify,
            focusFirst: false, foregroundBundleID: "com.spotify.client"), .fallback)
        for command in [MediaPlaybackCommand.next, .previous] {
            XCTAssertEqual(MusicPlaybackDispatch.resolve(command: command, preferred: .spotify,
                focusFirst: false, foregroundBundleID: "com.vivaldi.Vivaldi"), .fallback)
        }
        XCTAssertEqual(MusicPlaybackDispatch.resolve(command: .playPause, preferred: .system,
            focusFirst: false, foregroundBundleID: "com.vivaldi.Vivaldi"), .fallback)
    }
    func testExperimentalFocusFirstStillAppliesToEveryPlaybackCommand() {
        for command in MediaPlaybackCommand.allCases {
            XCTAssertEqual(MusicPlaybackDispatch.resolve(command: command, preferred: .system,
                focusFirst: true, foregroundBundleID: "com.spotify.client"), .focused)
        }
    }
}
