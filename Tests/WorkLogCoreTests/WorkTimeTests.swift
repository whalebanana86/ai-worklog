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

        // 기간 보고서는 이틀에 나뉜 세션을 한 줄로 합쳐도 두 날의 AI 일한 시간을 모두 센다.
        let reportEntries: [Double] = WorkLogAnalytics.entriesBySession(WorkLogAnalytics.days([s])).map(\.activeSeconds)
        XCTAssertEqual(reportEntries, [2820])
    }

    private func storeURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("worktime-\(UUID().uuidString)/worklog.sqlite")
    }

    private func rawSpans(_ url: URL) throws -> String? {
        var text: String?
        try SQLiteReader(writablePath: url.path).query("SELECT spans FROM sessions") { text = $0.string(0) }
        return text
    }

    func testStoreKeepsSpans() throws {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var s = WorkSession(tool: .codex, sessionId: "c", title: "t", cwd: "/p", projectPath: "/p", start: t0, end: t0.addingTimeInterval(900),
                            prompts: [PromptEntry(date: t0, text: "요청")])
        s.spans = [span(0, 900)]
        let store = try WorkLogStore(url: url)
        try store.save(sessions: [s], sources: [:], notesByRoot: [:])

        let loaded = try XCTUnwrap(try WorkLogStore(url: url).loadSessions()[s.id])
        XCTAssertEqual(loaded.spans, s.spans)
        XCTAssertEqual(loaded.activeSeconds, 960)
        // start·end 칸처럼 1970년 기준 초로 둔다.
        XCTAssertEqual(try rawSpans(url), "[[1791000000,1791000900]]")
    }

    func testOldSpanFormatIsRewrittenOnOpen() throws {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var s = WorkSession(tool: .codex, sessionId: "c", title: "t", cwd: "/p", projectPath: "/p", start: t0, end: t0.addingTimeInterval(900),
                            prompts: [PromptEntry(date: t0, text: "요청")])
        s.spans = [span(0, 900)]
        try WorkLogStore(url: url).save(sessions: [s], sources: [:], notesByRoot: [:])
        // 1.7.0 이 남긴 모양: {start, end}, 2001년 기준 초 (1_791_000_000 - 978_307_200)
        try SQLiteReader(writablePath: url.path).exec(#"UPDATE sessions SET spans = '[{"end":812693700,"start":812692800}]'"#)

        let loaded = try XCTUnwrap(try WorkLogStore(url: url).loadSessions()[s.id])
        XCTAssertEqual(loaded.spans, s.spans)
        XCTAssertEqual(try rawSpans(url), "[[1791000000,1791000900]]")
    }

    func testArchivedSessionWithoutSpansKeepsItsStoredTime() throws {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cal = Calendar.current
        let day1 = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 10))!
        let day2 = cal.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 10))!
        let s = WorkSession(tool: .claudeCode, sessionId: "old", title: "t", cwd: "/p", projectPath: "/p", start: day1, end: day2,
                            prompts: [PromptEntry(date: day1, text: "첫날"), PromptEntry(date: day2, text: "이튿날")])
        try WorkLogStore(url: url).save(sessions: [s], sources: [:], notesByRoot: [:])
        // 1.7 전 보관본: 구간은 없고, 그때 기록 줄마다 잰 작업 시간 20분만 남아 있다.
        try SQLiteReader(writablePath: url.path).exec("UPDATE sessions SET active_seconds = 1200, spans = '[]'")

        // 요청 시각으로만 재면 1분 + 1분이지만, 남아 있던 20분을 날마다 같은 비율로 나눠 쓴다.
        let loaded = try XCTUnwrap(try WorkLogStore(url: url).loadSessions()[s.id])
        XCTAssertEqual(loaded.activeSeconds, 1200)
        let perDay: [Double] = WorkLogAnalytics.days([loaded]).map(\.activeSeconds)
        XCTAssertEqual(perDay, [600, 600])

        // 다시 읽어도 구간이 생기지 않으면 그대로 이어 받고, 다시 저장해도 줄지 않는다.
        var reread = loaded
        reread.archivedTimeScale = nil
        let merged = reread.merged(withArchived: loaded)
        XCTAssertEqual(merged, loaded)
        try WorkLogStore(url: url).save(sessions: [merged], sources: [:], notesByRoot: [:])
        XCTAssertEqual(try XCTUnwrap(try WorkLogStore(url: url).loadSessions()[s.id]).activeSeconds, 1200)

        // 입력 기록만 남은 세션은 예전에도 요청 시각으로 쟀으니 저장값을 따르지 않는다.
        try SQLiteReader(writablePath: url.path).exec("UPDATE sessions SET has_transcript = 0, active_seconds = 1200")
        XCTAssertEqual(try XCTUnwrap(try WorkLogStore(url: url).loadSessions()[s.id]).activeSeconds, 120)
    }

    func testLMStudioCountsUntilTheLastChange() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lmstudio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let message: [String: Any] = ["versions": [["role": "user", "content": [["type": "text", "text": "질문"]]]], "currentlySelectedVersion": 0]
        let data = try JSONSerialization.data(withJSONObject: ["createdAt": t0.timeIntervalSince1970 * 1000, "messages": [message]])
        // 만든 뒤 9분 동안 주고받으면 1분 + 9분, 두 시간 뒤에 다시 고쳤으면 1분씩 두 번
        let changedAfter: [TimeInterval] = [540, 7200]
        let expected: [Double] = [600, 120]
        for (offset, seconds) in zip(changedAfter, expected) {
            let url = dir.appendingPathComponent("\(Int(offset)).conversation.json")
            try data.write(to: url)
            try FileManager.default.setAttributes([.modificationDate: t0.addingTimeInterval(offset)], ofItemAtPath: url.path)
            let s = try XCTUnwrap(LMStudioSource(root: dir).parse(url))
            XCTAssertEqual(s.activeSeconds, seconds)
        }
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
