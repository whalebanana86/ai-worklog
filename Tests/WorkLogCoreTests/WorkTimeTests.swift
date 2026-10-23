import XCTest
@testable import WorkLogCore

/// 작업 시간: 요청 시각과 AI 가 일한 구간(응답 시간)을 이어 재고, 10분 넘게 빈 곳은 뺀다.
final class WorkTimeTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_791_000_000)

    private func iso(_ offset: TimeInterval) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: t0.addingTimeInterval(offset))
    }

    private func user(_ text: String, at offset: TimeInterval) -> [String: Any] {
        ["type": "user", "message": ["role": "user", "content": text], "timestamp": iso(offset), "origin": ["kind": "human"]]
    }

    private func assistant(_ id: String, at offset: TimeInterval) -> [String: Any] {
        ["type": "assistant", "timestamp": iso(offset),
         "message": ["id": id, "model": "claude-x", "role": "assistant", "content": [["type": "text", "text": "답 \(id)"]]]]
    }

    private func turn(at offset: TimeInterval, ms: Int) -> [String: Any] {
        ["type": "system", "subtype": "turn_duration", "durationMs": ms, "timestamp": iso(offset)]
    }

    private func span(_ a: TimeInterval, _ b: TimeInterval) -> WorkSpan {
        WorkSpan(start: t0.addingTimeInterval(a), end: t0.addingTimeInterval(b))
    }

    func testWithoutSpansItMatchesTheRequestClock() {
        var clock = ActiveClock()
        let offsets: [TimeInterval] = [0, 300, 7500]
        let points = offsets.map { t0.addingTimeInterval($0) }
        points.forEach { clock.tick($0) }
        XCTAssertEqual(ActiveClock.seconds(points: points, spans: []), clock.seconds)
    }

    func testAIWorkAndShortGapsCount() {
        // 0초에 요청 → AI 가 20분 일함 → 5분 뒤 다시 요청 → 5분 일함
        let offsets: [TimeInterval] = [0, 1500]
        let points = offsets.map { t0.addingTimeInterval($0) }
        // 요청 시각만 보면 25분 틈을 쉰 걸로 봐서 1분 + 1분
        XCTAssertEqual(ActiveClock.seconds(points: points, spans: []), 120)
        // 구간까지 보면 처음부터 끝까지 30분 + 1분
        XCTAssertEqual(ActiveClock.seconds(points: points, spans: [span(0, 1200), span(1500, 1800)]), 1860)
    }

    func testTurnDurationIsTrimmedToRecordedWork() throws {
        var acc = ClaudeAccumulator(sessionId: "T")
        let lines: [[String: Any]] = [
            // ① 평범한 응답: 5분 1초
            user("첫 요청", at: 0), assistant("a1", at: 30), assistant("a2", at: 300), turn(at: 301, ms: 301_000),
            // ② 허락을 기다리며 30분 자리를 비운 응답: 기록이 끊긴 30분은 뺀다
            user("둘째 요청", at: 3600), assistant("b1", at: 3610), assistant("b2", at: 5410), turn(at: 5460, ms: 1_860_000),
            // ③ 걸린 시간이 사흘로 잘못 남은 응답: 앞 응답이 끝난 뒤, 기록이 이어진 곳만
            user("셋째 요청", at: 7200), assistant("c1", at: 7260), turn(at: 7320, ms: 259_200_000),
        ]
        lines.forEach { acc.ingest($0) }
        let s = try XCTUnwrap(acc.makeSession(sourcePath: "/x.jsonl", subagents: 0))

        XCTAssertEqual(s.spans, [span(0, 301), span(3600, 3610), span(5410, 5460), span(7200, 7320)])
        // 덩어리 4개마다 1분 + 301초 + 10초 + 50초 + 120초
        XCTAssertEqual(s.activeSeconds, 721)
    }

    func testSpansCountOnTheDayOfTheirRequest() throws {
        let cal = Calendar.current
        let day1 = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 23, minute: 50))!
        let day2 = cal.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 10))!
        var s = WorkSession(tool: .claudeCode, sessionId: "m", title: "t", cwd: "/p", projectPath: "/p", start: day1, end: day2,
                            prompts: [PromptEntry(date: day1, text: "밤 요청"), PromptEntry(date: day2, text: "아침 요청")])
        // 밤 요청으로 자정을 넘겨 40분, 아침 요청으로 5분
        s.spans = [WorkSpan(start: day1, end: day1.addingTimeInterval(2400)), WorkSpan(start: day2, end: day2.addingTimeInterval(300))]

        // 아침: 1분 + 5분, 밤: 1분 + 40분 (자정을 넘긴 일도 요청한 날에 센다)
        let perDay: [Double] = WorkLogAnalytics.days([s]).map(\.activeSeconds)
        XCTAssertEqual(perDay, [360, 2460])
        XCTAssertEqual(s.activeSeconds, 2820)

        let morning = DateInterval(start: cal.startOfDay(for: day2), duration: 86_400)
        let clipped = try XCTUnwrap(WorkLogAnalytics.clip([s], to: morning).first)
        XCTAssertEqual(clipped.spans, [s.spans[1]])
        XCTAssertEqual(clipped.activeSeconds, 360)
    }

    func testStoreKeepsSpans() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("worktime-\(UUID().uuidString)/worklog.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var s = WorkSession(tool: .codex, sessionId: "c", title: "t", cwd: "/p", projectPath: "/p", start: t0, end: t0.addingTimeInterval(900),
                            prompts: [PromptEntry(date: t0, text: "요청")])
        s.spans = [span(0, 900)]
        let store = try WorkLogStore(url: url)
        try store.save(sessions: [s], sources: [:], notesByRoot: [:])

        let loaded = try XCTUnwrap(try WorkLogStore(url: url).loadSessions()[s.id])
        XCTAssertEqual(loaded.spans, s.spans)
        XCTAssertEqual(loaded.activeSeconds, 960)
    }

    func testMergeKeepsSpansOfLostPrompts() {
        var old = WorkSession(tool: .codex, sessionId: "x", title: "t", cwd: "/", projectPath: "/", start: t0, end: t0.addingTimeInterval(4000),
                              prompts: [PromptEntry(date: t0, text: "옛 요청"), PromptEntry(date: t0.addingTimeInterval(3600), text: "새 요청")])
        old.spans = [span(0, 100), span(3600, 3700)]
        var fresh = old
        fresh.prompts = [PromptEntry(date: t0.addingTimeInterval(3600), text: "새 요청")]
        fresh.spans = [span(3600, 3750)]
        XCTAssertEqual(fresh.merged(withArchived: old).spans, [span(0, 100), span(3600, 3750)])
    }
}
