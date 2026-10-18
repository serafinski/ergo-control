import XCTest
import ApplicationServices
import ErgoCore
@testable import ErgoControl

final class PreferredMusicPlaybackTests: XCTestCase {
    // AX handles are inert identities here; tests never read or act on a UI.
    private func snapshot(enabled: Bool = true) -> MediaAccessibilitySnapshot {
        let nodes: [MediaControlNode] = [.init(parent: nil),
            .init(parent: 0, control: .previous), .init(parent: 0, control: .playPause, enabled: enabled),
            .init(parent: 0, control: .next)]
        return .init(nodes: nodes, elements: nodes.indices.map { AXUIElementCreateApplication(pid_t($0 + 1)) },
                     discovery: MediaControlDiscovery.find(in: nodes))
    }
    func testOneEnabledTransportControlIsSelected() {
        let player = snapshot()
        let selected = PreferredMusicPlayback.playbackControl(in: [player])
        XCTAssertNotNil(selected)
        XCTAssertTrue(CFEqual(selected!, player.elements[2]))
    }
    func testMultiplePlayersIncompleteReadsAndDisabledControlsNeverSelectAnArbitraryButton() {
        XCTAssertNil(PreferredMusicPlayback.playbackControl(in: nil))
        XCTAssertNil(PreferredMusicPlayback.playbackControl(in: []))
        XCTAssertNil(PreferredMusicPlayback.playbackControl(in: [snapshot(), nil]))
        XCTAssertNil(PreferredMusicPlayback.playbackControl(in: [snapshot(), snapshot()]))
        XCTAssertNil(PreferredMusicPlayback.playbackControl(in: [snapshot(enabled: false)]))
        let ambiguous = MediaAccessibilitySnapshot(nodes: [], elements: [], discovery: .ambiguous)
        XCTAssertNil(PreferredMusicPlayback.playbackControl(in: [snapshot(), ambiguous]))
    }
}
