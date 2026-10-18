import XCTest
import ErgoCore
@testable import ErgoControl

final class MusicFallbackControllerTests: XCTestCase {
    final class Rig {
        var queries: [(MediaTargetAvailability) -> Void] = []
        var opens: [MusicFallbackApplication] = []
        var openReplies: [(String?) -> Void] = []
        var native: [MediaPlaybackCommand] = []
        var notices: [String] = []
        var running: Set<MusicFallbackApplication> = []
        lazy var controller: MusicFallbackController = {
            let value = MusicFallbackController(query: { [unowned self] in queries.append($0) },
                open: { [unowned self] app, completion in opens.append(app); openReplies.append(completion) },
                isRunning: { [unowned self] in running.contains($0) },
                system: { [unowned self] in native.append($0) })
            value.onNotice = { [unowned self] in notices.append($0) }
            return value
        }()
    }
    func testSpotifyOpensOnlyWithNoTargetAndNeverSendsASecondPlayCommand() {
        let rig = Rig(); rig.controller.start(preferred: .spotify)
        rig.controller.perform(.playPause)
        XCTAssertTrue(rig.opens.isEmpty); XCTAssertTrue(rig.native.isEmpty)
        rig.queries[0](.none)
        XCTAssertEqual(rig.opens, [.spotify]); XCTAssertTrue(rig.native.isEmpty)
        rig.openReplies[0](nil)
        XCTAssertTrue(rig.native.isEmpty, "Opening the app must not also start an arbitrary track")
        XCTAssertTrue(rig.notices.isEmpty)
    }
    func testPausedOrPlayingTargetUsesNativePlaybackWithoutOpeningThePreferredApp() {
        let rig = Rig(); rig.controller.start(preferred: .spotify)
        rig.controller.perform(.playPause); rig.queries[0](.available)
        XCTAssertEqual(rig.native, [.playPause]); XCTAssertTrue(rig.opens.isEmpty)
    }
    func testUnknownTargetPreservesNativePlaybackAndMissingApplicationShowsNotice() {
        let rig = Rig(); rig.controller.start(preferred: .spotify)
        rig.controller.perform(.playPause); rig.queries[0](.unknown)
        XCTAssertEqual(rig.native, [.playPause]); XCTAssertTrue(rig.opens.isEmpty); XCTAssertTrue(rig.notices.isEmpty)
        rig.controller.perform(.playPause); rig.queries[1](.none)
        rig.openReplies[0]("Spotify is not installed")
        XCTAssertEqual(rig.notices.last, "Spotify is not installed")
        XCTAssertEqual(rig.native, [.playPause], "Missing app must not send another command")
    }
    func testOpenPreferredPlayerKeepsEveryPlayPausePressWithoutQueryingOrReopening() {
        for app in [MusicFallbackApplication.spotify, .music] {
            let rig = Rig(); rig.running.insert(app); rig.controller.start(preferred: app)
            rig.controller.perform(.playPause); rig.controller.perform(.playPause)
            XCTAssertEqual(rig.native, [.playPause, .playPause])
            XCTAssertTrue(rig.queries.isEmpty); XCTAssertTrue(rig.opens.isEmpty)
        }
    }
    func testPressAfterIdleLaunchControlsThePlayerEvenWithoutPublishedMediaTarget() {
        let rig = Rig(); rig.controller.start(preferred: .spotify)
        rig.controller.perform(.playPause); rig.queries[0](.none)
        rig.running.insert(.spotify); rig.openReplies[0](nil)
        rig.controller.perform(.playPause); rig.controller.perform(.playPause)
        XCTAssertEqual(rig.opens, [.spotify]); XCTAssertEqual(rig.queries.count, 1)
        XCTAssertEqual(rig.native, [.playPause, .playPause])
    }
    func testPlayerOpeningDuringQueryKeepsNativePlaybackInsteadOfReopeningIt() {
        let rig = Rig(); rig.controller.start(preferred: .spotify)
        rig.controller.perform(.playPause); rig.running.insert(.spotify)
        rig.queries[0](.none)
        XCTAssertTrue(rig.opens.isEmpty); XCTAssertEqual(rig.native, [.playPause])
    }
    func testSystemDefaultAndTrackNavigationBypassTheAvailabilityQuery() {
        let rig = Rig(); rig.controller.start(preferred: .system)
        for command in MediaPlaybackCommand.allCases { rig.controller.perform(command) }
        XCTAssertEqual(rig.native, MediaPlaybackCommand.allCases); XCTAssertTrue(rig.queries.isEmpty)
        rig.controller.start(preferred: .spotify)
        rig.controller.perform(.next); rig.controller.perform(.previous)
        XCTAssertTrue(rig.queries.isEmpty); XCTAssertTrue(rig.opens.isEmpty)
    }
    func testStopAndPreferenceChangesCancelLateQueriesAndLaunchReplies() {
        let rig = Rig(); rig.controller.start(preferred: .spotify)
        rig.controller.perform(.playPause)
        rig.controller.stop(); rig.queries[0](.none)
        XCTAssertTrue(rig.opens.isEmpty)
        rig.controller.start(preferred: .spotify)
        rig.controller.perform(.playPause); rig.queries[1](.none)
        rig.controller.start(preferred: .music)
        rig.openReplies[0]("Late launch error")
        XCTAssertTrue(rig.notices.isEmpty)
        rig.controller.perform(.playPause); rig.queries[2](.none)
        XCTAssertEqual(rig.opens, [.spotify, .music])
    }
    func testFocusedWindowChangeCancelsAnIdleFallbackBeforeItCanLaunch() {
        let rig = Rig(); rig.controller.start(preferred: .spotify)
        var focused = true
        rig.controller.perform(.playPause, stillCurrent: { focused })
        focused = false; rig.queries[0](.none)
        XCTAssertTrue(rig.opens.isEmpty); XCTAssertTrue(rig.native.isEmpty)
        rig.controller.perform(.playPause); rig.queries[1](.none)
        XCTAssertEqual(rig.opens, [.spotify])
    }
    func testRapidPressesCannotQueueDuplicateLaunchesWhileQueryOrLaunchIsPending() {
        let rig = Rig(); rig.controller.start(preferred: .spotify)
        rig.controller.perform(.playPause); rig.controller.perform(.playPause)
        XCTAssertEqual(rig.queries.count, 1)
        rig.queries[0](.none); rig.controller.perform(.playPause)
        XCTAssertEqual(rig.opens, [.spotify]); XCTAssertEqual(rig.queries.count, 1)
        rig.openReplies[0](nil)
        rig.controller.perform(.playPause)
        XCTAssertEqual(rig.queries.count, 2)
    }
    func testMediaActionRoutesOnceAndLeavesVolumeAndMuteOnNativePath() {
        let rig = Rig(); rig.controller.start(preferred: .spotify)
        var native: [ConsumerKeyEvent] = []
        let engine = ActionEngine(mediaOutput: { native.append(ConsumerKeyEvent($0, pressed: $1)) })
        engine.onPlayback = { rig.controller.perform($0) }
        engine.perform(MappingAction(.media, "playPause"))
        XCTAssertEqual(rig.queries.count, 1); XCTAssertTrue(native.isEmpty)
        rig.queries[0](.none); rig.openReplies[0](nil)
        for usage: UInt16 in [0xe9, 0xea, 0xe2] {
            _ = engine.media(usage, pressed: true); _ = engine.media(usage, pressed: false)
        }
        XCTAssertEqual(native.count, 6); XCTAssertEqual(rig.opens, [.spotify]); XCTAssertTrue(rig.native.isEmpty)
        engine.stop()
    }
}
