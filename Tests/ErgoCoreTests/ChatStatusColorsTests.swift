import XCTest
import ErgoCore

final class ChatStatusColorsTests: XCTestCase {
    func testDefaultsMatchSelectedPaletteAndDistinguishAllClaudeStates() {
        let codex = ChatStatusColors.defaults(for: .codex), claude = ChatStatusColors.defaults(for: .claude)
        XCTAssertEqual(codex.working, CodexActivity.working.color)
        XCTAssertEqual(codex.attention, CodexActivity.attention.color)
        XCTAssertEqual(codex.finished, CodexActivity.finished.color)
        XCTAssertEqual(Set([codex.working, codex.attention, codex.finished,
                            claude.working, claude.attention, claude.finished].map(\.bytes)).count, 6)
    }
    func testPaletteRoundTripsAndOldSettingsRetainProviderDefaults() throws {
        var settings = CodexSettings()
        let old = try JSONDecoder().decode(CodexSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertNil(old.statusColors)
        var palette = ChatStatusColors.defaults(for: .claude)
        palette.set(DialColor(red: 4, green: 5, blue: 6), for: .attention)
        settings.statusColors = palette
        XCTAssertEqual(try JSONDecoder().decode(CodexSettings.self, from: JSONEncoder().encode(settings)).statusColors, palette)
        XCTAssertEqual(palette.color(for: .attention), DialColor(red: 4, green: 5, blue: 6))
        XCTAssertEqual(palette.color(for: .idle), CodexActivity.idle.color)
    }
    func testCustomWaveHeadsAndTrailsUseTheRequestedRGB() {
        let color = DialColor(red: 90, green: 180, blue: 240)
        for speed in CodexWaveSpeed.allCases {
            for activity in [CodexActivity.working, .attention, .finished] {
                let frame = CodexStatusWave.frame(1, activity: activity, speed: speed, darkBackground: true, color: color)
                let head = CodexStatusWave.positions(for: activity, speed: speed)[1]
                XCTAssertEqual(frame[head], color)
                let width = speed == .quick ? 10 : 7
                XCTAssertEqual(frame[head - 1], DialColor(red: UInt8(90 * (width - 1) / width),
                                                         green: UInt8(180 * (width - 1) / width),
                                                         blue: UInt8(240 * (width - 1) / width)))
                XCTAssertEqual(frame[18], DialColor(red: 0, green: 0, blue: 0))
            }
        }
    }
}
