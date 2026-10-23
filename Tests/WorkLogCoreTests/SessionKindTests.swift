import XCTest
@testable import WorkLogCore

/// 어떤 세션을 사람이 한 작업으로 보여 주고, 어떤 것을 자동 실행(보조 호출·시험 도구)으로 숨기는지.
/// 기록 안의 작업 폴더는 글자일 뿐이라, 임시 폴더가 아닌 경로(/Users/demo/…)를 적어 쓴다.
final class SessionKindTests: XCTestCase {
    var root: URL!
    var projects: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("worklog-kind-\(UUID().uuidString)")
        projects = root.appendingPathComponent(".claude/projects/-demo")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ id: String, _ lines: [[String: Any]]) throws {
        let text = try lines.map { String(data: try JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! }.joined(separator: "\n") + "\n"
        try text.write(to: projects.appendingPathComponent("\(id).jsonl"), atomically: true, encoding: .utf8)
    }

    private func user(_ id: String, _ text: String, at ts: String, cwd: String, entrypoint: String,
                      extra: [String: Any] = [:]) -> [String: Any] {
        var o: [String: Any] = ["type": "user", "sessionId": id, "cwd": cwd, "entrypoint": entrypoint, "timestamp": ts,
                                "userType": "external", "message": ["role": "user", "content": [["type": "text", "text": text]]]]
        o.merge(extra) { $1 }
        return o
    }

    private func reply(_ id: String, _ text: String, at ts: String, cwd: String, entrypoint: String) -> [String: Any] {
        ["type": "assistant", "sessionId": id, "cwd": cwd, "entrypoint": entrypoint, "timestamp": ts,
         "message": ["id": "m-\(id)-\(ts)", "role": "assistant", "model": "claude-x", "content": [["type": "text", "text": text]],
                     "usage": ["input_tokens": 1, "output_tokens": 1]]]
    }

    private func sessions() throws -> [String: WorkSession] {
        let loader = WorkLogLoader(claude: ClaudeCodeSource(root: root.appendingPathComponent(".claude")),
                                   codex: CodexSource(root: root.appendingPathComponent("no-codex")),
                                   lmStudio: LMStudioSource(root: root.appendingPathComponent("no-lmstudio")),
                                   storeURL: root.appendingPathComponent("store/worklog.sqlite"))
        return Dictionary(uniqueKeysWithValues: loader.load().sessions.map { ($0.sessionId, $0) })
    }

    /// Agent SDK 로 만든 앱(데스크톱 GUI 등)에서 사람이 쓴 요청: promptSource 가 "sdk" 이고 origin 이 없어도 사람 작업으로 보인다.
    func testAgentSDKAppSessionWithHumanRequestsIsShown() throws {
        let sdk: [String: Any] = ["promptSource": "sdk", "turnOrigin": "sdk"]
        let cwd = "/Users/demo/work/app"
        try write("gui", [
            user("gui", "로그인 화면 만들어줘", at: "2026-10-20T23:12:08.000Z", cwd: cwd, entrypoint: "sdk-ts", extra: sdk),
            reply("gui", "만들었어요", at: "2026-10-20T23:20:00.000Z", cwd: cwd, entrypoint: "sdk-ts"),
            // AI 가 일하는 중에 들어온 백그라운드 작업 알림은 사람 요청이 아니다.
            ["type": "attachment", "sessionId": "gui", "cwd": cwd, "entrypoint": "sdk-ts", "timestamp": "2026-10-20T23:21:00.000Z",
             "attachment": ["type": "queued_command", "prompt": "<task-notification>끝남</task-notification>",
                            "origin": ["kind": "task-notification", "producer": "session-task"]]],
            user("gui", "버튼 색도 바꿔줘", at: "2026-10-20T23:30:00.000Z", cwd: cwd, entrypoint: "sdk-ts", extra: sdk),
        ])
        let s = try XCTUnwrap(try sessions()["gui"])
        XCTAssertFalse(s.isAutomated)
        XCTAssertEqual(s.userPrompts.map(\.text), ["로그인 화면 만들어줘", "버튼 색도 바꿔줘"])
        XCTAssertTrue(s.userPrompts.allSatisfy { !$0.isAutomated })
    }

    /// `claude -p`(sdk-cli)로 부른 보조 호출(대화 제목·브랜치 이름 짓기)은 지금처럼 숨긴다.
    func testPrintModeHelperCallsStayHidden() throws {
        let cwd = "/Users/demo/work/app"
        try write("namer", [
            user("namer", "Name this chat from the user's first request", at: "2026-10-20T23:12:09.000Z", cwd: cwd, entrypoint: "sdk-cli",
                 extra: ["promptSource": "sdk", "permissionMode": "plan"]),
            reply("namer", "로그인 화면", at: "2026-10-20T23:12:10.000Z", cwd: cwd, entrypoint: "sdk-cli"),
        ])
        XCTAssertTrue(try XCTUnwrap(try sessions()["namer"]).isAutomated)
    }

    /// 시험 도구(E2E)는 임시 폴더에서 돌린다. 사람이 친 것처럼 기록돼도(origin human, typed) 숨긴다. 터미널 세션도 같다.
    func testTestToolSessionsInTemporaryFoldersAreHidden() throws {
        let human: [String: Any] = ["origin": ["kind": "human"], "promptSource": "typed", "turnOrigin": "human"]
        try write("e2e-sdk", [
            user("e2e-sdk", "이 대화의 암호 단어는 X 야", at: "2026-10-20T23:48:00.000Z", cwd: "/private/tmp/e2e/demo-claude", entrypoint: "sdk-ts", extra: human),
        ])
        try write("e2e-cli", [
            user("e2e-cli", "README.md 의 첫 줄만 답해", at: "2026-10-21T00:01:40.000Z", cwd: "/private/tmp/e2e/demo", entrypoint: "cli", extra: human),
        ])
        try write("work", [
            user("work", "README 고쳐줘", at: "2026-10-21T00:05:00.000Z", cwd: "/Users/demo/work/app", entrypoint: "cli", extra: human),
        ])
        let all = try sessions()
        XCTAssertTrue(try XCTUnwrap(all["e2e-sdk"]).isAutomated)
        XCTAssertTrue(try XCTUnwrap(all["e2e-cli"]).isAutomated)
        XCTAssertFalse(try XCTUnwrap(all["work"]).isAutomated)
    }

    /// 터미널 세션에 프로그램이 끼워 넣은 글(promptSource "sdk")은 예전처럼 자동으로 본다.
    func testInjectedPromptInTerminalSessionStaysAutomated() throws {
        let cwd = "/Users/demo/work/app"
        try write("term", [
            user("term", "테스트 돌려줘", at: "2026-10-21T00:10:00.000Z", cwd: cwd, entrypoint: "cli", extra: ["origin": ["kind": "human"]]),
            user("term", "자동으로 들어온 글", at: "2026-10-21T00:11:00.000Z", cwd: cwd, entrypoint: "cli", extra: ["promptSource": "sdk"]),
        ])
        let s = try XCTUnwrap(try sessions()["term"])
        XCTAssertFalse(s.isAutomated)
        XCTAssertEqual(s.userPrompts.map(\.isAutomated), [false, true])
    }

    /// 임시 폴더 판정: 도구와 상관없이 cwd 로 본다. 이름만 비슷한 폴더(/tmpfoo)는 아니다.
    func testScratchFolderRule() {
        for path in ["/tmp", "/tmp/x", "/private/tmp/aiterm-e2e/demo-codex", "/var/folders/p5/abc/T/run", "/private/var/folders/x"] {
            XCTAssertTrue(WorkSession.isScratchFolder(path), path)
        }
        for path in ["", "/tmpfoo", "/Users/demo/tmp/x", "/var/log", "/Users/demo/Workspaces/apps/ai_terminal"] {
            XCTAssertFalse(WorkSession.isScratchFolder(path), path)
        }
        let day = Date()
        let codex = WorkSession(tool: .codex, sessionId: "c", title: "t", cwd: "/private/tmp/e2e/demo-codex", projectPath: "/private/tmp/e2e/demo-codex",
                                start: day, end: day, prompts: [PromptEntry(date: day, text: "암호 단어는 Y")])
        XCTAssertTrue(codex.isAutomated, "Codex 시험 세션도 숨긴다")
    }
}
