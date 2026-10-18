import XCTest
import ErgoCore
@testable import ErgoControl

final class MusicFallbackControllerTests: XCTestCase {
    final class Rig {
        var opens: [MusicFallbackApplication] = []
        var openReplies: [(String?) -> Void] = []
        var native: [MediaPlaybackCommand] = []
        var notices: [String] = []
        var running: Set<MusicFallbackApplication> = []
        var playback: [MusicFallbackApplication] = []
        var playbackReplies: [(String?) -> Void] = []
        var playbackCurrent: [() -> Bool] = []
        lazy var controller: MusicFallbackController = {
            let value = MusicFallbackController(
                open: { [unowned self] app, completion in opens.append(app); openReplies.append(completion) },
                isRunning: { [unowned self] in running.contains($0) },
                playback: { [unowned self] app, current, completion in
                    playback.append(app); playbackCurrent.append(current); playbackReplies.append(completion)
                }, system: { [unowned self] in native.append($0) })
            value.onNotice = { [unowned self] in notices.append($0) }
            return value
        }()
    }
    func testColdSpotifyLaunchNeverIssuesAGlobalPlayOrStartsATrack() {
        let rig = Rig(); rig.controller.start(preferred: .spotify)
        rig.controller.perform(.playPause)
        XCTAssertEqual(rig.opens, [.spotify]); XCTAssertTrue(rig.native.isEmpty)
        rig.openReplies[0](nil)
        XCTAssertTrue(rig.native.isEmpty); XCTAssertTrue(rig.playback.isEmpty)
    }
    func testOpenPreferredPlayerAlwaysUsesItsOwnPlaybackControl() {
        for app in [MusicFallbackApplication.spotify, .music] {
            let rig = Rig(); rig.running.insert(app); rig.controller.start(preferred: app)
            for index in 0..<2 { rig.controller.perform(.playPause); rig.playbackReplies[index](nil) }
            XCTAssertEqual(rig.playback, [app, app]); XCTAssertTrue(rig.native.isEmpty); XCTAssertTrue(rig.opens.isEmpty)
        }
    }
    func testMissingAppDoesNotLaunchAnotherPlayer() {
        let rig = Rig(); rig.controller.start(preferred: .spotify)
        rig.controller.perform(.playPause); rig.openReplies[0]("Spotify is not installed")
        XCTAssertEqual(rig.notices, ["Spotify is not installed"]); XCTAssertTrue(rig.native.isEmpty)
    }
    func testLaunchThenPlayPauseUsesPreferredAppWithoutAnyGlobalCommand() {
        let rig = Rig(); rig.controller.start(preferred: .spotify)
        rig.controller.perform(.playPause); rig.running.insert(.spotify); rig.openReplies[0](nil)
        for index in 0..<2 { rig.controller.perform(.playPause); rig.playbackReplies[index](nil) }
        XCTAssertEqual(rig.opens, [.spotify]); XCTAssertEqual(rig.playback, [.spotify, .spotify]); XCTAssertTrue(rig.native.isEmpty)
    }
    func testClosingThePlayerAfterPlaybackReturnsToPreferredLaunch() {
        let rig = Rig(); rig.running.insert(.spotify); rig.controller.start(preferred: .spotify)
        rig.controller.perform(.playPause); rig.playbackReplies[0](nil)
        rig.running.remove(.spotify); rig.controller.perform(.playPause)
        XCTAssertEqual(rig.opens, [.spotify]); XCTAssertTrue(rig.native.isEmpty)
    }
    func testSystemDefaultKeepsNativePlayback() {
        let rig = Rig(); rig.controller.start(preferred: .system)
        for command in MediaPlaybackCommand.allCases { rig.controller.perform(command) }
        XCTAssertEqual(rig.native, MediaPlaybackCommand.allCases); XCTAssertTrue(rig.opens.isEmpty); XCTAssertTrue(rig.playback.isEmpty)
    }
    func testExplicitPreferredAppKeepsTrackNavigationNative() {
        let rig = Rig(); rig.controller.start(preferred: .spotify)
        rig.controller.perform(.next); rig.controller.perform(.previous)
        XCTAssertEqual(rig.native, [.next, .previous]); XCTAssertTrue(rig.opens.isEmpty); XCTAssertTrue(rig.playback.isEmpty)
    }
    func testUncertainPreferredPressNeverFallsThroughToGlobalPlay() {
        let rig = Rig(); rig.running.insert(.spotify); rig.controller.start(preferred: .spotify)
        rig.controller.perform(.playPause); rig.playbackReplies[0]("Press not confirmed")
        XCTAssertTrue(rig.native.isEmpty); XCTAssertEqual(rig.notices, ["Press not confirmed"])
    }
    func testStopAndPreferenceChangeInvalidateLatePlaybackAndLaunchResults() {
        let rig = Rig(); rig.running.insert(.spotify); rig.controller.start(preferred: .spotify)
        rig.controller.perform(.playPause); XCTAssertTrue(rig.playbackCurrent[0]())
        rig.controller.stop(); XCTAssertFalse(rig.playbackCurrent[0]()); rig.playbackReplies[0]("Late press error")
        rig.controller.start(preferred: .music); rig.controller.perform(.playPause)
        rig.controller.start(preferred: .spotify); rig.openReplies[0]("Late launch error")
        XCTAssertTrue(rig.notices.isEmpty); XCTAssertTrue(rig.native.isEmpty)
    }
    func testChangedFocusCancelsPreferredPlaybackBeforeItCanAct() {
        let rig = Rig(); rig.running.insert(.spotify); rig.controller.start(preferred: .spotify)
        var focused = true
        rig.controller.perform(.playPause, stillCurrent: { focused }); focused = false
        XCTAssertFalse(rig.playbackCurrent[0]()); rig.playbackReplies[0]("Stale result")
        rig.controller.perform(.playPause, stillCurrent: { false })
        XCTAssertEqual(rig.playback.count, 1); XCTAssertTrue(rig.notices.isEmpty)
    }
    func testRapidPressesDoNotDuplicateLaunchesOrPlaybackWhilePending() {
        let rig = Rig(); rig.controller.start(preferred: .spotify)
        rig.controller.perform(.playPause); rig.controller.perform(.playPause)
        XCTAssertEqual(rig.opens, [.spotify])
        rig.running.insert(.spotify); rig.openReplies[0](nil)
        rig.controller.perform(.playPause); rig.controller.perform(.playPause)
        XCTAssertEqual(rig.playback, [.spotify]); XCTAssertTrue(rig.native.isEmpty)
    }
    func testStoppedControllerIgnoresCommands() {
        let rig = Rig(); rig.controller.start(preferred: .spotify); rig.controller.stop()
        rig.controller.perform(.playPause)
        XCTAssertTrue(rig.opens.isEmpty); XCTAssertTrue(rig.native.isEmpty); XCTAssertTrue(rig.playback.isEmpty)
    }
    func testMediaActionRoutesOnceAndLeavesVolumeAndMuteOnNativePath() {
        let rig = Rig(); rig.controller.start(preferred: .spotify)
        var native: [ConsumerKeyEvent] = []
        let engine = ActionEngine(mediaOutput: { native.append(ConsumerKeyEvent($0, pressed: $1)) })
        engine.onPlayback = { rig.controller.perform($0) }
        engine.perform(MappingAction(.media, "playPause")); rig.openReplies[0](nil)
        for usage: UInt16 in [0xe9, 0xea, 0xe2] {
            _ = engine.media(usage, pressed: true); _ = engine.media(usage, pressed: false)
        }
        XCTAssertEqual(native.count, 6); XCTAssertEqual(rig.opens, [.spotify]); XCTAssertTrue(rig.native.isEmpty)
        engine.stop()
    }
}
