import XCTest
@testable import ErgoCore

final class MediaPlaybackRoutingTests: XCTestCase {
    private var transport: [MediaControlNode] {
        [.init(parent: nil), .init(parent: 0, control: .previous),
         .init(parent: 0, control: .playPause), .init(parent: 0, control: .next)]
    }
    func testEnglishAndPolishTransportLabelsDoNotMatchPlaylistOrBrowserNavigation() {
        for label in ["Play", "Pause (k)", " Play / pause ", "Odtwórz", "Wstrzymaj (k)", "Wznów"] {
            XCTAssertEqual(MediaControl.button(labels: [label]), .playPause)
        }
        XCTAssertEqual(MediaControl.button(labels: ["Next (SHIFT+n)"]), .next)
        XCTAssertEqual(MediaControl.button(labels: ["Poprzedni"]), .previous)
        XCTAssertEqual(MediaControl.button(labels: ["Wyłącz wyciszenie"]), .mute)
        for label in ["Play playlist Foo", "Odtwórz utwór Foo", "Playback settings", "Next page", "Poprzednia strona", "Back", "Forward", "Playground"] {
            XCTAssertNil(MediaControl.button(labels: [label]), label)
        }
        XCTAssertNil(MediaControl.slider(labels: ["Zoom level"]))
        XCTAssertEqual(MediaControl.slider(labels: ["Zmień postęp"]), .timeline)
    }
    func testTransportBarWinsOverUnrelatedPlaylistPlayButtons() {
        let nodes: [MediaControlNode] = [.init(parent: nil), .init(parent: 0),
            .init(parent: 1, control: .previous), .init(parent: 1, control: .playPause), .init(parent: 1, control: .next),
            .init(parent: 0), .init(parent: 5, control: .playPause), .init(parent: 0), .init(parent: 7, control: .playPause)]
        guard case .player(let group) = MediaControlDiscovery.find(in: nodes) else { return XCTFail("Transport was not found") }
        XCTAssertEqual(group.root, 1); XCTAssertEqual(group.playPause, 3)
        XCTAssertEqual(group.next, 4); XCTAssertEqual(group.previous, 2)
    }
    func testVideoTransportWithMuteCanPauseAndResumeWithoutNextOrPrevious() {
        for label in ["Play (k)", "Pause (k)"] {
            let nodes: [MediaControlNode] = [.init(parent: nil),
                .init(parent: 0, control: MediaControl.button(labels: [label])), .init(parent: 0, control: .mute)]
            guard case .player(let group) = MediaControlDiscovery.find(in: nodes) else { return XCTFail("Video transport missing") }
            XCTAssertEqual(group.playPause, 1)
            XCTAssertNil(group.next); XCTAssertNil(group.previous)
        }
    }
    func testAmbiguousPlayersAndBarePlayButtonsAreNotArbitrarilyClicked() {
        XCTAssertEqual(MediaControlDiscovery.find(in: [.init(parent: nil), .init(parent: 0, control: .playPause)]), .none)
        let nodes: [MediaControlNode] = [.init(parent: nil), .init(parent: 0),
            .init(parent: 1, control: .playPause), .init(parent: 1, control: .mute), .init(parent: 0),
            .init(parent: 4, control: .playPause), .init(parent: 4, control: .mute)]
        XCTAssertEqual(MediaControlDiscovery.find(in: nodes), .ambiguous)
        XCTAssertEqual(MediaPlaybackRoute.resolve(command: .playPause, focused: .ambiguous,
                                                  remembered: MediaControlDiscovery.find(in: transport)), .unavailable)
    }
    func testFocusedMediaWinsThenLastMediaThenSystemTarget() {
        let player = MediaControlDiscovery.find(in: transport)
        for command in MediaPlaybackCommand.allCases {
            XCTAssertEqual(MediaPlaybackRoute.resolve(command: command, focused: player, remembered: player), .focused)
            XCTAssertEqual(MediaPlaybackRoute.resolve(command: command, focused: .none, remembered: player), .remembered)
            XCTAssertEqual(MediaPlaybackRoute.resolve(command: command, focused: .none, remembered: .none), .system)
            XCTAssertEqual(MediaPlaybackCommand(usage: command.usage), command)
        }
        XCTAssertNil(MediaPlaybackCommand(usage: 0xe9)); XCTAssertNil(MediaPlaybackCommand(usage: 0xe2))
    }
    func testUnavailableNextDoesNotSkipADifferentBackgroundPlayer() {
        let foreground = MediaControlDiscovery.find(in: [.init(parent: nil), .init(parent: 0, control: .playPause), .init(parent: 0, control: .mute)])
        let background = MediaControlDiscovery.find(in: transport)
        XCTAssertEqual(MediaPlaybackRoute.resolve(command: .next, focused: foreground, remembered: background), .unavailable)
        XCTAssertEqual(MediaPlaybackRoute.resolve(command: .previous, focused: foreground, remembered: background), .unavailable)
        XCTAssertEqual(MediaPlaybackRoute.resolve(command: .playPause, focused: foreground, remembered: background), .focused)
    }
    func testDisabledControlRemainsOwnedByItsPlayerRatherThanFallingBack() {
        var nodes = transport
        nodes[3] = .init(parent: 0, control: .next, enabled: false)
        let discovery = MediaControlDiscovery.find(in: nodes)
        guard case .player(let group) = discovery else { return XCTFail("Disabled transport disappeared") }
        XCTAssertEqual(group.next, 3)
        XCTAssertFalse(nodes[group.next!].enabled)
        XCTAssertEqual(MediaPlaybackRoute.resolve(command: .next, focused: discovery, remembered: .none), .focused)
    }
    func testMediaCommandsFollowWindowChangesRatherThanStickingToFirstPlayer() {
        let music = MediaControlDiscovery.find(in: transport)
        let video = MediaControlDiscovery.find(in: [.init(parent: nil), .init(parent: 0, control: .playPause), .init(parent: 0, control: .mute)])
        // Music → video pause → video resume → ordinary window → music again.
        for (focused, remembered, expected): (MediaControlDiscovery, MediaControlDiscovery, MediaPlaybackRoute) in [
            (music,.none,.focused), (video,music,.focused), (video,video,.focused), (.none,video,.remembered), (music,video,.focused)
        ] {
            XCTAssertEqual(MediaPlaybackRoute.resolve(command: .playPause, focused: focused, remembered: remembered), expected)
        }
    }
}
