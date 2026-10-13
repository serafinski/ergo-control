import XCTest
@testable import ErgoCore

final class KeyboardSnapshotTests: XCTestCase {
    func testCapturedAAndReleaseSnapshots() {
        XCTAssertEqual(KeyboardSnapshot(Data([1,0,4,0,0,0,0,0,0,0,0,0]))?.held, [4])
        XCTAssertEqual(KeyboardSnapshot(Data([1,0,0,0,0,0,0,0,0,0,0,0]))?.held, [])
    }
    func testModifierChordsAndRolloverSafety() {
        let snapshot = KeyboardSnapshot(Data([1,10,6,6,0,0,0,0,0,0,0,0]))
        XCTAssertEqual(snapshot?.held, [6,225,227]); XCTAssertEqual(snapshot?.modifiers, 10)
        XCTAssertNil(KeyboardSnapshot(Data([1,0,1,1,1,1,1,1,1,1,1,1])))
        XCTAssertNil(KeyboardSnapshot(Data([1,0])))
        XCTAssertNil(KeyboardSnapshot(Data([5,0,4,0,0,0,0,0,0,0,0,0])))
    }
}
