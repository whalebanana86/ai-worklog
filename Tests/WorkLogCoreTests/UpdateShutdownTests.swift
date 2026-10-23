import XCTest
@testable import WorkLogCore

final class UpdateShutdownTests: XCTestCase {
    @MainActor
    func testRefusedTerminationReturnsControlForCleanupAndRetry() async {
        var helperWaiting = true
        var installing = true
        var events: [String] = []
        await UpdateShutdown.request(settleNanoseconds: 1, graceNanoseconds: 1, terminate: {
            events.append("termination requested")
            // Model AppKit refusing to quit while the sheet was modal.
            XCTAssertTrue(installing)
        }, stillRunning: {
            events.append("helper canceled")
            helperWaiting = false
            installing = false
        })
        XCTAssertEqual(events, ["termination requested", "helper canceled"])
        XCTAssertFalse(helperWaiting)
        XCTAssertFalse(installing)
    }

    @MainActor
    func testRefusedQuitCancelsARealWaitingProcess() async throws {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        helper.arguments = ["30"]
        try helper.run()
        await UpdateShutdown.request(settleNanoseconds: 1, graceNanoseconds: 1, terminate: {}, stillRunning: {
            await UpdateShutdown.cancelWaitingHelper(helper)
        })
        XCTAssertFalse(helper.isRunning)
        XCTAssertEqual(helper.terminationReason, .uncaughtSignal)
    }

}
