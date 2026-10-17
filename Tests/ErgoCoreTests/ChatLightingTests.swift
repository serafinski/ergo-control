import XCTest
@testable import ErgoCore

final class ChatLightingTests: XCTestCase {
    private func event(_ name: String, _ time: TimeInterval, session: String = "one", turn: String? = "turn-a") -> CodexHookEvent {
        CodexHookEvent(sessionID: session, turnID: turn, event: name, project: "Example", time: Date(timeIntervalSince1970: time))
    }
    private func candidate(_ state: CodexSessionStatus, _ provider: ChatProvider, now: TimeInterval = 110) -> ChatLightingCandidate {
        ChatLightingCandidate(provider: provider, session: state, now: Date(timeIntervalSince1970: now))!
    }
    func testNewestTurnWinsUntilItFinishesThenOlderWorkResumes() {
        var arbiter = ChatLightingArbiter()
        let claude = candidate(CodexSessionStatus(event("UserPromptSubmit", 100)), .claude)
        var codexState = CodexSessionStatus(event("UserPromptSubmit", 102))
        let codex = candidate(codexState, .codex)
        XCTAssertEqual(arbiter.select([claude], mode: .automatic), claude)
        XCTAssertEqual(arbiter.select([claude, codex], mode: .automatic), codex)
        codexState.receive(event("Stop", 109))
        let done = candidate(codexState, .codex)
        XCTAssertEqual(arbiter.select([done, claude], mode: .automatic), claude)
        XCTAssertNil(arbiter.select([done], mode: .automatic), "A completion hidden by ongoing work must not replay later")
        var claudeState = CodexSessionStatus(event("UserPromptSubmit", 100))
        claudeState.receive(event("Stop", 110))
        XCTAssertEqual(arbiter.select([candidate(claudeState, .claude), done], mode: .automatic)?.provider, .claude)
    }
    func testApprovalPreemptsNewerWorkAndMostRecentApprovalWins() {
        var arbiter = ChatLightingArbiter()
        let olderApproval = candidate(CodexSessionStatus(event("PermissionRequest", 100)), .claude)
        let work = candidate(CodexSessionStatus(event("UserPromptSubmit", 108)), .codex)
        XCTAssertEqual(arbiter.select([work, olderApproval], mode: .automatic), olderApproval)
        let newerApproval = candidate(CodexSessionStatus(event("PermissionRequest", 109)), .codex)
        XCTAssertEqual(arbiter.select([olderApproval, newerApproval], mode: .automatic), newerApproval)
        XCTAssertEqual(arbiter.select([olderApproval], mode: .automatic), olderApproval)
    }
    func testToolEventsAndApprovalResumptionDoNotChangeTurnRecency() {
        var claude = CodexSessionStatus(event("UserPromptSubmit", 100))
        let codex = candidate(CodexSessionStatus(event("UserPromptSubmit", 102)), .codex)
        claude.receive(event("PreToolUse", 103))
        var arbiter = ChatLightingArbiter()
        XCTAssertEqual(arbiter.select([candidate(claude, .claude), codex], mode: .automatic), codex)
        claude.receive(event("PermissionRequest", 104))
        XCTAssertEqual(arbiter.select([candidate(claude, .claude), codex], mode: .automatic)?.provider, .claude)
        claude.receive(event("PreToolUse", 105))
        XCTAssertEqual(claude.turnStarted, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(claude.workingSince, Date(timeIntervalSince1970: 105))
        XCTAssertEqual(arbiter.select([candidate(claude, .claude), codex], mode: .automatic), codex)
        claude.receive(event("UserPromptSubmit", 106, turn: "turn-b"))
        XCTAssertEqual(arbiter.select([candidate(claude, .claude), codex], mode: .automatic)?.provider, .claude)
    }
    func testManualModeExcludesOtherAppWithoutBlockingCompletion() {
        var arbiter = ChatLightingArbiter()
        let attention = candidate(CodexSessionStatus(event("PermissionRequest", 100)), .claude)
        let done = candidate(CodexSessionStatus(event("Stop", 109)), .codex)
        XCTAssertEqual(arbiter.select([attention, done], mode: .codex), done)
        XCTAssertEqual(arbiter.select([attention, done], mode: .claude), attention)
        XCTAssertTrue(ChatLightingMode.automatic.includes(.codex)); XCTAssertTrue(ChatLightingMode.automatic.includes(.claude))
    }
    func testTiesAreStableAndProviderNamespaceSeparatesIdenticalSessionIDs() {
        let state = CodexSessionStatus(event("UserPromptSubmit", 100))
        let a = candidate(state, .codex), b = candidate(state, .claude)
        XCTAssertNotEqual(a.id, b.id)
        var arbiter = ChatLightingArbiter()
        XCTAssertEqual(arbiter.select([a, b], mode: .automatic), arbiter.select([b, a], mode: .automatic))
    }
    func testExpiryRemovesWorkAndCompletionButKeepsPendingApproval() {
        let now = Date(timeIntervalSince1970: 2000)
        XCTAssertNil(ChatLightingCandidate(provider: .codex, session: CodexSessionStatus(event("UserPromptSubmit", 100)), now: now))
        XCTAssertNil(ChatLightingCandidate(provider: .claude, session: CodexSessionStatus(event("Stop", 100)), now: now))
        XCTAssertNotNil(ChatLightingCandidate(provider: .claude, session: CodexSessionStatus(event("PermissionRequest", 100)), now: now))
    }
}
