import XCTest
@testable import ErgoControl

final class PreferredMusicPlaybackTests: XCTestCase {
    func testEnglishAndPolishNativePlayPauseMenuActionsAreRecognised() {
        for name in ["Play", "Pause", "Play / pause", "Odtwórz", "Pauza", "Wstrzymaj"] {
            let menu = [(labels: ["Next"], enabled: true), (labels: [name], enabled: true)]
            XCTAssertEqual(PreferredMusicPlayback.menuPlaybackIndex(in: menu), 1)
        }
    }
    func testMissingDisabledAndDuplicateActionsNeverSelectAnArbitraryCommand() {
        XCTAssertNil(PreferredMusicPlayback.menuPlaybackIndex(in: []))
        XCTAssertNil(PreferredMusicPlayback.menuPlaybackIndex(in: [(labels: ["Play playlist Foo"], enabled: true)]))
        XCTAssertNil(PreferredMusicPlayback.menuPlaybackIndex(in: [(labels: ["Play"], enabled: false)]))
        XCTAssertNil(PreferredMusicPlayback.menuPlaybackIndex(in: [(labels: ["Play"], enabled: true), (labels: ["Pause"], enabled: true)]))
    }
}
