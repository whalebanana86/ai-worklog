import XCTest
@testable import WorkLogCore

/// 프로젝트 화면 머리·정보 패널 숫자: 위쪽 기간 버튼에 맞춰 그 기간 요청만 센다.
final class ProjectPeriodTotalsTests: XCTestCase {
    private let calendar = Calendar.current

    private func session(_ id: String, _ tool: AITool, day: Int, prompts count: Int) -> WorkSession {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 10))!
        let prompts = (0..<count).map { PromptEntry(date: start.addingTimeInterval(Double($0) * 300), text: "요청 \($0)") }
        return WorkSession(tool: tool, sessionId: id, title: "t", cwd: "/p", projectPath: "/p",
                           start: start, end: prompts.last!.date, prompts: prompts)
    }

    func testCountsOnlyThePeriod() throws {
        let project = ProjectSummary(path: "/p", sessions: [session("a", .claudeCode, day: 5, prompts: 2),
                                                            session("b", .codex, day: 20, prompts: 3)], notes: [])
        let all = project.totals(in: nil)
        XCTAssertEqual(all.totals.sessions, 2)
        XCTAssertEqual(all.totals.prompts, 5)
        XCTAssertEqual(all.totals.activeDays, 2)
        XCTAssertEqual(all.tools, [.claudeCode, .codex])

        let week = DateInterval(start: calendar.date(from: DateComponents(year: 2026, month: 10, day: 16))!,
                                end: calendar.date(from: DateComponents(year: 2026, month: 10, day: 23))!)
        let recent = project.totals(in: week)
        XCTAssertEqual(recent.totals.sessions, 1)
        XCTAssertEqual(recent.totals.prompts, 3)
        XCTAssertEqual(recent.totals.activeDays, 1)
        XCTAssertEqual(recent.tools, [.codex])
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(recent.first), inSameDayAs: week.start.addingTimeInterval(4 * 86_400)))
        XCTAssertEqual(recent.last, project.sessions[1].prompts.last?.date)

        // 그 기간에 요청이 없으면 0, 첫·마지막 요청도 없다.
        let empty = project.totals(in: DateInterval(start: week.start, duration: 3_600))
        XCTAssertEqual(empty.totals.prompts, 0)
        XCTAssertNil(empty.first)
        XCTAssertTrue(empty.tools.isEmpty)
    }
}
