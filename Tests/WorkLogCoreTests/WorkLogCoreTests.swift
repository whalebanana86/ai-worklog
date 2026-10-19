import XCTest
@testable import WorkLogCore

/// 가짜 ~/.claude 를 임시 폴더에 만들어 읽기·보관함 동작을 확인한다.
final class WorkLogCoreTests: XCTestCase {
    var root: URL!
    var claudeDir: URL!
    var project: String!
    var transcript: URL!
    var storeURL: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("worklog-test-\(UUID().uuidString)")
        claudeDir = root.appendingPathComponent(".claude")
        project = root.appendingPathComponent("proj").path
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let projectsDir = claudeDir.appendingPathComponent("projects/-tmp-proj")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        transcript = projectsDir.appendingPathComponent("S1.jsonl")
        storeURL = root.appendingPathComponent("store/worklog.sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - 도우미

    private func json(_ object: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    private func append(_ lines: [[String: Any]], newline: Bool = true) throws {
        let text = lines.map(json).joined(separator: "\n") + (newline ? "\n" : "")
        if let handle = try? FileHandle(forWritingTo: transcript) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try handle.close()
        } else {
            try text.write(to: transcript, atomically: true, encoding: .utf8)
        }
    }

    private func user(_ text: String, at ts: String, origin: String? = "human") -> [String: Any] {
        var o: [String: Any] = ["type": "user", "message": ["role": "user", "content": text], "timestamp": ts,
                                "cwd": project!, "sessionId": "S1", "gitBranch": "main"]
        if let origin { o["origin"] = ["kind": origin] }
        return o
    }

    private func assistant(id: String, at ts: String, content: [[String: Any]]) -> [String: Any] {
        ["type": "assistant", "timestamp": ts, "cwd": project!, "sessionId": "S1",
         "message": ["id": id, "model": "claude-x", "role": "assistant", "content": content,
                     "usage": ["input_tokens": 10, "output_tokens": 5]]]
    }

    private func firstSession() throws -> [[String: Any]] {
        [
            user("첫 요청\n<pasted_content id=\"a1\">\n붙인 글\n</pasted_content id=\"a1\">", at: "2026-10-16T01:00:00.000Z"),
            assistant(id: "m1", at: "2026-10-16T01:00:05.000Z", content: [["type": "tool_use", "name": "Skill", "input": ["skill": "dataviz"]]]),
            // 같은 답변의 다음 조각: 사용량이 또 붙어 있지만 한 번만 세야 한다.
            assistant(id: "m1", at: "2026-10-16T01:00:06.000Z", content: [["type": "tool_use", "name": "Edit",
                                                                          "input": ["file_path": project + "/a.swift", "old_string": "a", "new_string": "b\nc"]]]),
            ["type": "user", "toolUseResult": [:], "timestamp": "2026-10-16T01:00:07.000Z",
             "message": ["role": "user", "content": [["type": "tool_result", "content": "ok"]]]],
            assistant(id: "m2", at: "2026-10-16T01:01:00.000Z", content: [["type": "text", "text": "완료했어요"]]),
            ["type": "ai-title", "aiTitle": "테스트 세션", "sessionId": "S1"],
            user("<command-name>/feature</command-name><command-message>feature</command-message><command-args>로그인 추가</command-args>",
                 at: "2026-10-16T01:02:00.000Z", origin: nil),
            user("<command-name>/login</command-name><command-args></command-args>", at: "2026-10-16T01:02:30.000Z", origin: nil),
            user("<task-notification>끝남</task-notification>", at: "2026-10-16T01:03:00.000Z", origin: "task-notification"),
            // AI 가 일하는 도중에 보낸 메시지
            ["type": "attachment", "timestamp": "2026-10-16T01:04:00.000Z", "cwd": project!, "sessionId": "S1",
             "attachment": ["type": "queued_command", "prompt": "그리고 이것도 해 줘", "origin": ["kind": "human"]]],
            ["type": "api-request-blob", "sessionId": "S1", "message": ["role": "user", "content": "아주 큰 사본"]],
        ]
    }

    private func makeLoader() -> WorkLogLoader {
        WorkLogLoader(claude: ClaudeCodeSource(root: claudeDir),
                      codex: CodexSource(root: root.appendingPathComponent("no-codex")),
                      lmStudio: LMStudioSource(root: root.appendingPathComponent("no-lmstudio")),
                      storeURL: storeURL)
    }

    private func session(_ snapshot: WorkLogSnapshot, _ id: String = "S1") throws -> WorkSession {
        try XCTUnwrap(snapshot.sessions.first { $0.sessionId == id })
    }

    // MARK: - 읽기

    func testParsesHumanPromptsRepliesFilesAndSkills() throws {
        try append(firstSession())
        let s = try session(makeLoader().load())

        XCTAssertEqual(s.title, "테스트 세션")
        XCTAssertEqual(s.gitBranch, "main")
        XCTAssertEqual(s.userPrompts.map(\.text).last, "그리고 이것도 해 줘", "작업 도중 보낸 메시지도 요청이다")
        XCTAssertEqual(s.userPrompts.count, 2, "명령·알림·도구 결과는 사람 요청이 아니다")
        XCTAssertEqual(s.prompts.count, 3, "인자 있는 /feature 는 남고 /login 은 빠진다")
        XCTAssertEqual(s.prompts[1].text, "/feature 로그인 추가")
        XCTAssertTrue(s.prompts[1].isCommand)

        let first = s.prompts[0]
        XCTAssertEqual(first.reply, "완료했어요")
        XCTAssertTrue(first.text.contains("〔붙여넣은 내용〕"))
        XCTAssertTrue(first.text.contains("붙인 글"))
        XCTAssertFalse(first.text.contains("pasted_content"))
        XCTAssertEqual(first.files, [project + "/a.swift"])
        XCTAssertEqual(first.linesAdded, 2)
        XCTAssertEqual(first.linesRemoved, 1)

        XCTAssertEqual(s.files.map(\.path), [project + "/a.swift"])
        XCTAssertEqual(s.skillsUsed, ["dataviz": 1, "feature": 1], "/login 같은 기본 명령은 스킬로 세지 않는다")
        XCTAssertEqual(s.models["claude-x"]?.inputTokens, 20, "같은 메시지 id 의 사용량은 한 번만")
        XCTAssertEqual(s.models["claude-x"]?.outputTokens, 10)
    }

    func testReadsOnlyAppendedPartAndWaitsForUnfinishedLine() throws {
        try append(firstSession())
        let loader = makeLoader()
        XCTAssertEqual(try session(loader.load()).userPrompts.count, 2)

        // 아직 줄바꿈이 안 붙은(쓰는 중인) 줄은 읽지 않는다.
        try append([user("두 번째 요청", at: "2026-10-16T02:00:00.000Z")], newline: false)
        XCTAssertEqual(try session(loader.load()).userPrompts.count, 2)

        // 줄 끝이 붙고 답변이 이어지면, 아까 멈춘 자리부터 읽는다.
        let handle = try FileHandle(forWritingTo: transcript)
        handle.seekToEndOfFile()
        handle.write(Data("\n".utf8))
        try handle.close()
        try append([assistant(id: "m3", at: "2026-10-16T02:00:10.000Z", content: [["type": "text", "text": "두 번째 답"]])])
        let s = try session(loader.load())
        XCTAssertEqual(s.userPrompts.map(\.text).last, "두 번째 요청")
        XCTAssertEqual(s.userPrompts.last?.reply, "두 번째 답")
    }

    func testIncrementalAppendMatchesFullRead() throws {
        try append(firstSession())
        let loader = makeLoader()
        _ = loader.load()
        try append([user("세 번째", at: "2026-10-16T03:00:00.000Z"),
                    assistant(id: "m9", at: "2026-10-16T03:00:20.000Z", content: [["type": "text", "text": "세 번째 답"]])])
        let incremental = try session(loader.load())

        let fresh = WorkLogLoader(claude: ClaudeCodeSource(root: claudeDir), codex: CodexSource(root: root), lmStudio: LMStudioSource(root: root), storeURL: nil)
        let full = try session(fresh.load())
        XCTAssertEqual(incremental.prompts, full.prompts)
        XCTAssertEqual(incremental.models, full.models)
        XCTAssertEqual(incremental.skillsUsed, full.skillsUsed)
    }

    // MARK: - 보관함

    func testResumeAfterRestartUsesArchivedPromptsWithoutDuplicating() throws {
        try append(firstSession())
        _ = makeLoader().load()

        // 읽기 상태에는 요청 글이 들어 있지 않아야 한다 (보관함 prompts 표와 중복 저장 금지).
        let store = try WorkLogStore(url: storeURL)
        // 임시 폴더는 /var/… 와 /private/var/… 두 가지로 적히므로 경로 대신 하나뿐인 상태를 꺼낸다.
        let state = try XCTUnwrap(try store.loadSources().values.first)
        XCTAssertTrue(state.accumulator.prompts.isEmpty)

        // 앱을 다시 켠 것처럼 새 로더로 늘어난 부분만 읽는다.
        try append([user("다시 켠 뒤 요청", at: "2026-10-16T05:00:00.000Z"),
                    assistant(id: "m7", at: "2026-10-16T05:00:30.000Z", content: [["type": "text", "text": "다시 켠 뒤 답"]])])
        let resumed = try session(makeLoader().load())
        let full = try session(WorkLogLoader(claude: ClaudeCodeSource(root: claudeDir), codex: CodexSource(root: root),
                                             lmStudio: LMStudioSource(root: root), storeURL: nil).load())
        XCTAssertEqual(resumed.prompts, full.prompts, "이어 읽은 결과가 처음부터 읽은 결과와 같아야 한다")
        XCTAssertEqual(resumed.prompts.first?.reply, "완료했어요")
        XCTAssertEqual(resumed.userPrompts.last?.reply, "다시 켠 뒤 답")
        XCTAssertEqual(resumed.models, full.models)
    }

    func testArchiveKeepsSessionAfterSourceIsDeleted() throws {
        try append(firstSession())
        _ = makeLoader().load()

        // Claude Code 가 오래된 대화 원본을 지운 상황
        try FileManager.default.removeItem(at: transcript)
        let afterDelete = try session(makeLoader().load())
        XCTAssertTrue(afterDelete.sourceMissing)
        XCTAssertTrue(afterDelete.hasTranscript)
        XCTAssertEqual(afterDelete.prompts.first?.reply, "완료했어요", "AI 답변까지 보관함에 남는다")

        // 앱을 다시 켜도(새 로더) 보관함에서 바로 보인다.
        let archived = try XCTUnwrap(makeLoader().loadArchived())
        let s = try session(archived)
        XCTAssertTrue(s.sourceMissing)
        XCTAssertEqual(s.skillsUsed["dataviz"], 1)
        XCTAssertEqual(s.title, "테스트 세션")
    }

    func testHistoryOnlySessionsDoNotReplaceArchivedTranscripts() throws {
        try append(firstSession())
        let history = [
            ["display": "첫 요청", "timestamp": 1_791_000_000_000.0, "project": project!, "sessionId": "S1"],
            ["display": "/status", "timestamp": 1_791_000_100_000.0, "project": project!, "sessionId": "S2"],
            ["display": "예전 작업", "timestamp": 1_791_000_200_000.0, "project": project!, "sessionId": "S2"],
        ].map(json).joined(separator: "\n") + "\n"
        try history.write(to: claudeDir.appendingPathComponent("history.jsonl"), atomically: true, encoding: .utf8)

        let loader = makeLoader()
        _ = loader.load()
        try FileManager.default.removeItem(at: transcript)
        let snap = makeLoader().load()

        let s1 = try session(snap, "S1")
        XCTAssertTrue(s1.hasTranscript, "원본이 지워져도 답변이 있는 보관본을 입력 기록으로 덮지 않는다")
        XCTAssertEqual(s1.prompts.first?.reply, "완료했어요")

        let s2 = try session(snap, "S2")
        XCTAssertFalse(s2.hasTranscript)
        XCTAssertEqual(s2.title, "예전 작업")
        XCTAssertEqual(s2.userPrompts.count, 1)
    }

    func testMergeNeverDropsArchivedPrompts() {
        let d0 = Date(timeIntervalSince1970: 1_000)
        let d1 = Date(timeIntervalSince1970: 2_000)
        let old = WorkSession(tool: .codex, sessionId: "x", title: "t", cwd: "/", projectPath: "/", start: d0, end: d1,
                              activeSeconds: 60, prompts: [PromptEntry(date: d0, text: "옛 요청"), PromptEntry(date: d1, text: "새 요청")])
        var fresh = old
        fresh.prompts = [PromptEntry(date: d1, text: "새 요청", reply: "답")]
        let merged = fresh.merged(withArchived: old)
        XCTAssertEqual(merged.prompts.map(\.text), ["옛 요청", "새 요청"])
        XCTAssertEqual(merged.prompts.last?.reply, "답")
    }

    func testReadsWALDatabaseAfterItsWriterClosed() throws {
        let path = root.appendingPathComponent("state.sqlite").path
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            let writer = try SQLiteReader(writablePath: path)
            try writer.exec("PRAGMA journal_mode=WAL; CREATE TABLE threads(id TEXT); INSERT INTO threads VALUES ('a'), ('b'); PRAGMA wal_checkpoint(TRUNCATE);")
        }
        // Codex 를 끈 뒤처럼 -wal·-shm 이 없는 WAL 방식 DB.
        try? FileManager.default.removeItem(atPath: path + "-wal")
        try? FileManager.default.removeItem(atPath: path + "-shm")
        let reader = try XCTUnwrap(SQLiteReader(path: path))
        var count = 0
        try reader.query("SELECT COUNT(*) FROM threads") { count = $0.int(0) }
        XCTAssertEqual(count, 2)
    }

    // MARK: - AI 날짜별 요약

    private func summaryDay() -> (sessions: [WorkSession], day: Date) {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 10))!
        var asked = PromptEntry(date: day, text: "로그인 **버그** 고쳐줘", reply: "알겠어요. 세션 만료 처리를 고쳤어요.")
        asked.files = ["/p/src/auth.ts"]
        let session = WorkSession(tool: .claudeCode, sessionId: "A", title: "로그인 버그", cwd: "/p", projectPath: "/p",
                                  start: day, end: day.addingTimeInterval(600), activeSeconds: 600, prompts: [
                                      PromptEntry(date: day.addingTimeInterval(-60), text: "/clear", isCommand: true),
                                      asked,
                                      PromptEntry(date: day.addingTimeInterval(300), text: "<task-notification>", isAutomated: true),
                                  ])
        var other = session
        other.sessionId = "B"
        other.projectPath = "/other"
        return ([session, other], day)
    }

    func testSummaryMaterialHasOnlyHumanRequestsOfThatProject() throws {
        let (sessions, day) = summaryDay()
        let source = try XCTUnwrap(DaySummarizer.source(project: "/p", day: day, sessions: sessions))
        XCTAssertEqual(source.entries.count, 1)
        XCTAssertEqual(DaySummarizer.promptCount(for: source), 1)
        let material = try XCTUnwrap(DaySummarizer.material(for: source, projectName: "p"))
        XCTAssertTrue(material.contains("요청: 로그인 버그 고쳐줘"))
        XCTAssertTrue(material.contains("결과: 세션 만료 처리를 고쳤어요."))
        XCTAssertTrue(material.contains("고친 파일: auth.ts"))
        XCTAssertFalse(material.contains("/clear"))
        XCTAssertFalse(material.contains("task-notification"))
        // 같은 재료는 같은 지문, 기록이 늘면 다른 지문.
        XCTAssertEqual(DaySummarizer.digest(material), DaySummarizer.digest(material))
        XCTAssertNotEqual(DaySummarizer.digest(material), DaySummarizer.digest(material + "- 11:00 요청: 하나 더\n"))
        // 사람이 보낸 요청이 없는 날은 요약하지 않는다.
        var onlyCommands = source
        onlyCommands.entries[0].prompts = onlyCommands.entries[0].prompts.filter(\.isCommand)
        XCTAssertNil(DaySummarizer.material(for: onlyCommands, projectName: "p"))
    }

    func testSummaryBacklogSkipsTodayAndSummarizedDays() throws {
        var (sessions, day) = summaryDay()
        var today = sessions[0]
        today.sessionId = "T"
        today.prompts = [PromptEntry(date: Date(), text: "오늘 한 요청")]
        today.start = Date()
        today.end = Date()
        sessions.append(today)

        let all = DaySummarizer.backlog(sessions: sessions, existing: [:])
        XCTAssertEqual(all.map(\.project), ["/other", "/p"])
        XCTAssertTrue(all.allSatisfy { Calendar.current.isDate($0.day, inSameDayAs: day) && $0.plan == .full })

        // 그날이 끝난 뒤 만든 요약은 마감된 것: 다시 하지 않는다.
        let key = DaySummary.key(project: "/p", day: Fmt.isoDay(day))
        let closed = DaySummary(project: "/p", day: Fmt.isoDay(day), digest: "", engine: "Claude Code", headline: "h", points: [],
                                promptCount: 1, coveredUntil: day, created: day.addingTimeInterval(86_400))
        XCTAssertEqual(DaySummarizer.backlog(sessions: sessions, existing: [key: closed]).map(\.project), ["/other"])
        // 일주일 안만 보면 오래된 날은 빠진다.
        XCTAssertTrue(DaySummarizer.backlog(sessions: sessions, existing: [:], since: Date().addingTimeInterval(-86_400)).isEmpty)
    }

    private func dayGroup(_ dates: [Date], texts: [String]? = nil) -> DayGroup {
        let prompts = dates.enumerated().map { PromptEntry(date: $1, text: texts?[$0] ?? "요청 \($0)") }
        let session = WorkSession(tool: .claudeCode, sessionId: "P", title: "t", cwd: "/p", projectPath: "/p",
                                  start: dates[0], end: dates[dates.count - 1], activeSeconds: 60, prompts: prompts)
        return DayGroup(day: Calendar.current.startOfDay(for: dates[0]), entries: [DayEntry(session: session, prompts: prompts)])
    }

    private func summary(promptCount: Int = 1, covered: Date?, created: Date) -> DaySummary {
        DaySummary(project: "/p", day: "d", digest: "", engine: "Claude Code", headline: "h", points: [],
                   promptCount: promptCount, coveredUntil: covered, created: created)
    }

    func testTodayWaitsUntilWorkPausesThenUpdatesOnlyNewRequests() throws {
        let now = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        // 아직 일하는 중(10분 전 요청): 마지막 요청 뒤 30분까지 기다린다. 버튼을 누르면 바로.
        let working = dayGroup([ago(40), ago(10)])
        XCTAssertEqual(DaySummarizer.plan(for: working, existing: nil, now: now), .wait(until: ago(-20)))
        XCTAssertEqual(DaySummarizer.plan(for: working, existing: nil, now: now, force: true), .full)
        // 손 뗀 지 30분이 지났으면 요약한다.
        XCTAssertEqual(DaySummarizer.plan(for: dayGroup([ago(50), ago(40)]), existing: nil, now: now), .full)

        // 요약이 있으면 그 뒤 요청만 더해 이어 쓴다. 일하는 중이면 역시 기다린다.
        let old = summary(covered: ago(80), created: ago(75))
        XCTAssertEqual(DaySummarizer.plan(for: dayGroup([ago(90), ago(80), ago(10)]), existing: old, now: now), .wait(until: ago(-20)))
        let paused = dayGroup([ago(90), ago(80), ago(45)])
        XCTAssertEqual(DaySummarizer.plan(for: paused, existing: old, now: now), .update(after: ago(80)))
        XCTAssertEqual(DaySummarizer.newSince(old, in: paused), 1)
        // 새 요청이 없으면 그대로, 버튼은 처음부터 다시.
        let current = summary(covered: ago(45), created: ago(10))
        XCTAssertEqual(DaySummarizer.plan(for: paused, existing: current, now: now), .keep)
        XCTAssertEqual(DaySummarizer.plan(for: paused, existing: current, now: now, force: true), .full)
    }

    func testPastDayIsClosedOnceThenKept() throws {
        let (_, day) = summaryDay()
        let group = dayGroup([day, day.addingTimeInterval(3_600)])
        let nextDay = day.addingTimeInterval(86_400)
        XCTAssertEqual(DaySummarizer.plan(for: group, existing: nil), .full)
        // 그날 도중에 만든 요약: 남은 요청을 더해 한 번 마감한다. 시각을 안 남긴 예전 요약은 요청 수로 어림한다.
        XCTAssertEqual(DaySummarizer.plan(for: group, existing: summary(covered: day, created: day.addingTimeInterval(600))), .update(after: day))
        XCTAssertEqual(DaySummarizer.plan(for: group, existing: summary(covered: nil, created: day.addingTimeInterval(600))), .update(after: day))
        // 그날이 끝난 뒤 만든 요약은 새 요청이 생겨도 그대로 둔다 (버튼으로만 이어 쓰기).
        let closed = summary(covered: day, created: nextDay)
        XCTAssertEqual(DaySummarizer.plan(for: group, existing: closed), .keep)
        XCTAssertEqual(DaySummarizer.plan(for: group, existing: closed, force: true), .update(after: day))
    }

    func testUpdateMaterialHasOnlyRequestsAfterSummary() throws {
        let (_, day) = summaryDay()
        let group = dayGroup([day, day.addingTimeInterval(3_600)], texts: ["앞 요청", "뒤 요청"])
        let rest = try XCTUnwrap(DaySummarizer.material(for: group, projectName: "p", after: day))
        XCTAssertTrue(rest.contains("뒤 요청"))
        XCTAssertFalse(rest.contains("앞 요청"))
        XCTAssertNil(DaySummarizer.material(for: group, projectName: "p", after: day.addingTimeInterval(3_600)))
    }

    func testSummaryParserReadsHeadlineAndPoints() throws {
        let plain = try XCTUnwrap(DaySummarizer.parse("로그인 버그를 고침.\n- 세션 만료 처리 고침\n- 테스트 3개 추가\n"))
        XCTAssertEqual(plain.headline, "로그인 버그를 고침")
        XCTAssertEqual(plain.points, ["세션 만료 처리 고침", "테스트 3개 추가"])

        let decorated = try XCTUnwrap(DaySummarizer.parse("<think>음…</think>\n\n**요약:** `auth.ts` 정리\n\n1. 첫째\n2) 둘째\n• 셋째"))
        XCTAssertEqual(decorated.headline, "auth.ts 정리")
        XCTAssertEqual(decorated.points, ["첫째", "둘째", "셋째"])

        let bulletsOnly = try XCTUnwrap(DaySummarizer.parse("- 하나\n- 둘"))
        XCTAssertEqual(bulletsOnly.headline, "하나")
        XCTAssertEqual(bulletsOnly.points, ["둘"])

        XCTAssertNil(DaySummarizer.parse("  \n```\n```"))
    }

    func testStoreKeepsDaySummaries() throws {
        let covered = Date(timeIntervalSince1970: 1_792_000_000)
        let summary = DaySummary(project: "/p", day: "2026-10-14", digest: "abc", engine: "Claude Code",
                                 headline: "로그인 버그 고침", points: ["세션 만료 처리 고침"], promptCount: 1, coveredUntil: covered)
        try WorkLogStore(url: storeURL).saveSummary(summary)
        var newer = summary
        newer.digest = "def"
        try WorkLogStore(url: storeURL).saveSummary(newer)
        let loaded = try WorkLogStore(url: storeURL).loadSummaries()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[summary.key]?.digest, "def")
        XCTAssertEqual(loaded[summary.key]?.points, ["세션 만료 처리 고침"])
        XCTAssertEqual(loaded[summary.key]?.coveredUntil, covered)
    }

    // MARK: - 자동 보관 · 시연 기록

    func testAutoSyncWritesAndRemovesLaunchAgent() throws {
        var sync = AutoSync(home: root)
        sync.useLaunchctl = false
        XCTAssertFalse(sync.isEnabled)
        try sync.enable(program: ["/Applications/AI 작업일지.app/Contents/MacOS/AIWorkLog", "cli", "--quiet"])
        XCTAssertTrue(sync.isEnabled)
        XCTAssertEqual(sync.registeredProgram, ["/Applications/AI 작업일지.app/Contents/MacOS/AIWorkLog", "cli", "--quiet"])
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: sync.agentURL), format: nil) as? [String: Any])
        XCTAssertEqual(plist["Label"] as? String, AutoSync.label)
        XCTAssertEqual(plist["StartInterval"] as? Int, 21_600)
        sync.disable()
        XCTAssertFalse(sync.isEnabled)
        XCTAssertNil(sync.registeredProgram)
    }

    func testDemoDataHasClosedPastDaysAndATodayWaitingForABreak() throws {
        let now = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!
        let snapshot = DemoData.snapshot(now: now)
        let summaries = DemoData.summaries(now: now)
        XCTAssertEqual(Set(snapshot.sessions.map(\.projectName)), ["todo-app", "my-blog", "weather-widget", "photo-album"])
        // 시연 기록은 지난 날을 다시 요약하지 않는다.
        XCTAssertTrue(DaySummarizer.backlog(sessions: snapshot.sessions, existing: summaries, now: now).isEmpty)
        // 오늘은 요청 3개까지 요약돼 있고, 12분 전 요청 하나가 "30분 쉬면" 이어 쓰기를 기다린다.
        let todo = DemoData.path("todo-app")
        let today = try XCTUnwrap(DaySummarizer.source(project: todo, day: now, sessions: snapshot.sessions))
        let summary = try XCTUnwrap(summaries[DaySummary.key(project: todo, day: Fmt.isoDay(now))])
        XCTAssertEqual(DaySummarizer.newSince(summary, in: today), 1)
        XCTAssertEqual(DaySummarizer.plan(for: today, existing: summary, now: now), .wait(until: now.addingTimeInterval(18 * 60)))
    }

    // MARK: - 화면 언어

    func testEveryScreenTextHasTranslations() throws {
        // 소스에서 L("…") 의 첫 글을 모두 모아 영어·일본어 표에 있는지, 빈자리(%@) 수가 같은지 본다.
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let pattern = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])L\("((?:[^"\\]|\\.)*)""#)
        var keys = Set<String>()
        for case let file as URL in FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)! where file.pathExtension == "swift" {
            // 주석 속 예시(L("…"))는 빼고 코드만 본다.
            let text = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let raw = String(text[Range(match.range(at: 1), in: text)!])
                keys.insert(raw.replacingOccurrences(of: #"\""#, with: "\"").replacingOccurrences(of: #"\n"#, with: "\n"))
            }
        }
        XCTAssertGreaterThan(keys.count, 300)
        func holes(_ s: String) -> Int { s.components(separatedBy: "@").count - 1 }
        for (name, table) in [("en", Translations.en), ("ja", Translations.ja)] {
            let missing = keys.filter { table[$0] == nil }.sorted()
            XCTAssertTrue(missing.isEmpty, "\(name) 번역이 없는 글: \(missing.prefix(10))")
            for key in keys { if let t = table[key] { XCTAssertEqual(holes(t), holes(key), "\(name): \(key) → \(t)") } }
        }
    }

    func testFillsHolesInOrderAndByNumber() {
        XCTAssertEqual(Loc.fill("%@ · %@", ["a", "b"]), "a · b")
        XCTAssertEqual(Loc.fill("%2$@ in %1$@", ["3", "rules"]), "rules in 3")
        XCTAssertEqual(Loc.fill("100%% %@", ["done"]), "100% done")
        XCTAssertEqual(Loc.text("오늘", in: .en), "Today")
        XCTAssertEqual(Loc.text("오늘", in: .ja), "今日")
        XCTAssertEqual(Loc.text("없는 열쇠", in: .en), "없는 열쇠")
        XCTAssertEqual(Loc.singularize("1 requests · 11 requests · 21 files · 1 days ago"), "1 request · 11 requests · 21 files · 1 day ago")
    }

    // MARK: - 설정 찾기

    func testFindsRulesSkillsCommandsAndHidesSettingValues() throws {
        let fm = FileManager.default
        try "# 규칙\n한국어로 답한다".write(toFile: project + "/CLAUDE.md", atomically: true, encoding: .utf8)
        try fm.createDirectory(atPath: project + "/.claude/skills/deploy/references", withIntermediateDirectories: true)
        try "---\nname: deploy\ndescription: 배포 절차\n---\n# 배포".write(toFile: project + "/.claude/skills/deploy/SKILL.md", atomically: true, encoding: .utf8)
        try "참고".write(toFile: project + "/.claude/skills/deploy/references/a.md", atomically: true, encoding: .utf8)
        try fm.createDirectory(atPath: project + "/.claude/commands", withIntermediateDirectories: true)
        try "기능을 만든다".write(toFile: project + "/.claude/commands/feature.md", atomically: true, encoding: .utf8)
        try json(["env": ["SECRET_TOKEN": "abc123"], "hooks": ["Stop": [["hooks": [["type": "command", "command": "say hi"]]]]],
                  "permissions": ["allow": ["Bash(ls)"]]])
            .write(toFile: project + "/.claude/settings.json", atomically: true, encoding: .utf8)

        let items = AIConfigScanner.scan(directory: project)
        let byKind = Dictionary(grouping: items, by: \.kind)
        XCTAssertEqual(byKind[.rule]?.first?.name, "CLAUDE.md")
        let skill = try XCTUnwrap(byKind[.skill]?.first)
        XCTAssertEqual(skill.name, "deploy")
        XCTAssertEqual(skill.summary, "배포 절차")
        XCTAssertEqual(skill.extraFiles, 2, "references 폴더와 그 안 파일")
        XCTAssertEqual(byKind[.command]?.first?.name, "/feature")
        let settings = try XCTUnwrap(byKind[.settings]?.first)
        XCTAssertTrue(settings.body.contains("`Stop` 1개"))
        XCTAssertFalse(settings.body.contains("abc123"), "비밀값은 보여 주지 않는다")
        XCTAssertFalse(settings.body.contains("say hi"))
    }

    // MARK: - 작은 것들

    func testFastDate() {
        XCTAssertEqual(FastDate.parse("2026-10-07T04:41:37.347Z")?.timeIntervalSince1970 ?? 0, 1_791_348_097.347, accuracy: 0.001)
        XCTAssertEqual(FastDate.parse("1970-01-01T00:00:00Z")?.timeIntervalSince1970, 0)
    }

    func testChatGPTHandoffIsCleaned() {
        let raw = "## Referenced ChatGPT conversation:\n긴 머리말\n## My request:\nContinuing from [감성 아이디어](chatgpt-conversation://x): 에셋 만들어 줘"
        XCTAssertEqual(CodexText.clean(raw), "(ChatGPT 「감성 아이디어」 이어서) 에셋 만들어 줘")
    }

    func testActiveClockSkipsLongBreaks() {
        var clock = ActiveClock()
        let t0 = Date(timeIntervalSince1970: 0)
        clock.tick(t0)
        clock.tick(t0.addingTimeInterval(300))      // 5분 뒤: 일한 시간
        clock.tick(t0.addingTimeInterval(300 + 7200)) // 2시간 쉼: 1분만 친다
        XCTAssertEqual(clock.seconds, 60 + 300 + 60)
    }
}
