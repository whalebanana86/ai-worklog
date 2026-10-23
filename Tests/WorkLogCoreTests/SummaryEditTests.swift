import XCTest
@testable import WorkLogCore

/// AI 요약을 사람이 고치거나 되돌리기: 전 판이 남는지, 고친 요약을 저절로 덮지 않는지, 보관함에 그대로 남는지.
final class SummaryEditTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("worklog-edit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 10))!

    private func summary(_ headline: String, covered: Date? = nil, created: Date? = nil) -> DaySummary {
        DaySummary(project: "/p", day: "2026-10-14", digest: "d-\(headline)", engine: "Claude Code", headline: headline,
                   points: ["\(headline) 결과"], promptCount: 1, coveredUntil: covered, created: created ?? day)
    }

    private func dayGroup(_ dates: [Date]) -> DayGroup {
        let prompts = dates.enumerated().map { PromptEntry(date: $1, text: "요청 \($0)") }
        let session = WorkSession(tool: .claudeCode, sessionId: "P", title: "t", cwd: "/p", projectPath: "/p",
                                  start: dates[0], end: dates[dates.count - 1], prompts: prompts)
        return DayGroup(day: Calendar.current.startOfDay(for: dates[0]), entries: [DayEntry(session: session, prompts: prompts)])
    }

    func testEditKeepsPreviousAndRevertGoesBackAndForth() throws {
        let ai = summary("AI 가 쓴 요약")
        let edited = ai.editing(headline: "내가 고친 요약", points: ["하나", "둘"], now: day.addingTimeInterval(60))
        XCTAssertEqual(edited.headline, "내가 고친 요약")
        XCTAssertTrue(edited.edited)
        XCTAssertTrue(edited.pinned)
        XCTAssertEqual(edited.previous?.headline, "AI 가 쓴 요약")

        // 되돌리면 AI 판으로, 한 번 더 되돌리면 다시 고친 판으로.
        let back = try XCTUnwrap(edited.revertedToPrevious())
        XCTAssertEqual(back.headline, "AI 가 쓴 요약")
        XCTAssertEqual(back.points, ["AI 가 쓴 요약 결과"])
        XCTAssertFalse(back.edited)
        XCTAssertTrue(back.pinned, "사람이 고른 판은 저절로 바꾸지 않는다")
        let forth = try XCTUnwrap(back.revertedToPrevious())
        XCTAssertEqual(forth.headline, "내가 고친 요약")
        XCTAssertTrue(forth.edited)
        XCTAssertNil(summary("처음").revertedToPrevious(), "전 판이 없으면 되돌릴 수 없다")
    }

    func testNewAISummaryKeepsTheOldOneForUndo() {
        let old = summary("아침 요약")
        let new = summary("저녁 요약").replacing(old)
        XCTAssertEqual(new.previous?.headline, "아침 요약")
        XCTAssertFalse(new.pinned)
        XCTAssertNil(summary("같은 글").replacing(summary("같은 글")).previous, "글이 같으면 전 판으로 남기지 않는다")
    }

    /// 고치거나 되돌린 요약은 새 요청이 생겨도 저절로 다시 쓰지 않는다. 버튼(force)을 누르면 이어 쓴다.
    func testPinnedSummaryIsNotUpdatedAutomatically() {
        let group = dayGroup([day, day.addingTimeInterval(3_600)])
        let nextDay = day.addingTimeInterval(86_400)
        let partial = summary("앞부분", covered: day, created: day.addingTimeInterval(600))
        XCTAssertEqual(DaySummarizer.plan(for: group, existing: partial, now: nextDay), .update(after: day), "고치지 않은 요약은 마감한다")
        let pinned = partial.editing(headline: "고친 앞부분", points: [], now: day.addingTimeInterval(700))
        XCTAssertEqual(DaySummarizer.plan(for: group, existing: pinned, now: nextDay), .keep)
        XCTAssertEqual(DaySummarizer.plan(for: group, existing: pinned, now: nextDay, force: true), .update(after: day))
        XCTAssertTrue(DaySummarizer.backlog(sessions: group.entries.map(\.session), existing: [pinned.key: pinned], now: nextDay).isEmpty)
    }

    /// 보관함: 고친 표시·전 판이 남고, 전 판을 정하지 않고 저장하면(터미널 요약) 있던 것을 전 판으로 남긴다.
    func testStoreKeepsEditsAndPreviousVersion() throws {
        let url = root.appendingPathComponent("worklog.sqlite")
        let store = try WorkLogStore(url: url)
        try store.saveSummary(summary("처음 요약"))
        try store.saveSummary(summary("새 요약"))
        var loaded = try XCTUnwrap(try store.loadSummaries()[summary("x").key])
        XCTAssertEqual(loaded.headline, "새 요약")
        XCTAssertEqual(loaded.previous?.headline, "처음 요약")

        try store.saveSummary(loaded.editing(headline: "고친 요약", points: ["가"]))
        loaded = try XCTUnwrap(try WorkLogStore(url: url).loadSummaries()[summary("x").key])
        XCTAssertEqual(loaded.headline, "고친 요약")
        XCTAssertTrue(loaded.edited)
        XCTAssertTrue(loaded.pinned)
        XCTAssertEqual(loaded.previous?.headline, "새 요약")
        XCTAssertEqual(loaded.previous?.points, ["새 요약 결과"])
    }

    /// 예전 보관함(고침·전 판 칸이 없던 때)도 열리고, 있던 요약은 그대로 읽힌다.
    func testOldArchiveGetsNewColumns() throws {
        let url = root.appendingPathComponent("old.sqlite")
        do {
            let db = try SQLiteReader(writablePath: url.path)
            try db.exec("""
                CREATE TABLE day_summaries (project TEXT NOT NULL, day TEXT NOT NULL, digest TEXT NOT NULL, engine TEXT NOT NULL,
                    headline TEXT NOT NULL, points TEXT NOT NULL DEFAULT '[]', prompt_count INTEGER NOT NULL DEFAULT 0,
                    created REAL NOT NULL, covered_until REAL, PRIMARY KEY (project, day));
                INSERT INTO day_summaries VALUES ('/p', '2026-10-14', 'd', 'Codex', '예전 요약', '["a"]', 2, 1000, NULL);
                """)
        }
        let loaded = try XCTUnwrap(try WorkLogStore(url: url).loadSummaries()[summary("x").key])
        XCTAssertEqual(loaded.headline, "예전 요약")
        XCTAssertFalse(loaded.edited)
        XCTAssertFalse(loaded.pinned)
        XCTAssertNil(loaded.previous)
    }
}
