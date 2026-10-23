import Foundation

/// OpenAI Codex 기록(~/.codex). 스레드 목록은 state_*.sqlite, 대화 내용은 thread_history_*.sqlite 에 있다.
public struct CodexSource {
    public let root: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        self.root = root
    }

    /// state_5.sqlite 처럼 숫자가 붙는데, 버전이 오르면 숫자가 바뀌므로 가장 큰 걸 고른다.
    func latestDatabase(prefix: String) -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let best = names
            .filter { $0.hasPrefix(prefix + "_") && $0.hasSuffix(".sqlite") }
            .max { version($0) < version($1) }
        return best.map { root.appendingPathComponent($0).path }
    }

    private func version(_ name: String) -> Int {
        Int(name.split(separator: "_").last?.split(separator: ".").first ?? "") ?? 0
    }

    public func load(warnings: inout [String]) -> [WorkSession] {
        guard let statePath = latestDatabase(prefix: "state") else { return [] }
        guard let state = SQLiteReader(path: statePath) else {
            warnings.append(L("Codex 스레드 목록을 열지 못했습니다: %@", statePath))
            return []
        }

        let names = threadNames()
        var sessions: [String: WorkSession] = [:]
        let hasName = state.hasColumn("threads", "name")
        let sql = """
            SELECT id, rollout_path, COALESCE(created_at_ms, created_at * 1000), COALESCE(updated_at_ms, updated_at * 1000),
                   source, cwd, title, tokens_used, model, git_branch, first_user_message, \(hasName ? "name" : "NULL")
            FROM threads
            """
        do {
            try state.query(sql) { row in
                guard let id = row.string(0) else { return }
                let start = Date(timeIntervalSince1970: Double(row.int(2)) / 1000)
                let end = Date(timeIntervalSince1970: Double(row.int(3)) / 1000)
                let source = row.string(4) ?? ""
                let cwd = row.string(5) ?? ""
                let firstMessage = row.string(10) ?? ""
                let title = [row.string(11), names[id], row.string(6), firstMessage]
                    .compactMap { $0.map(CodexText.title) }
                    .first { !$0.isEmpty } ?? "제목 없는 스레드"
                var models: [String: ModelUsage] = [:]
                models[row.string(8) ?? "codex"] = ModelUsage(unsplitTokens: row.int(7))
                sessions[id] = WorkSession(
                    tool: .codex,
                    sessionId: id,
                    title: title,
                    cwd: cwd,
                    projectPath: cwd,
                    gitBranch: row.string(9),
                    start: start,
                    end: end,
                    prompts: firstMessage.isEmpty ? [] : [PromptEntry(date: start, text: CodexText.clean(firstMessage), isAutomated: source == "exec")],
                    models: models,
                    sourcePath: row.string(1),
                    hasTranscript: false
                )
            }
        } catch {
            warnings.append(L("Codex 스레드 목록을 읽지 못했습니다: %@", "\(error)"))
            return []
        }

        fillDetails(&sessions, warnings: &warnings)

        return sessions.values.map { s in
            var s = s
            let edits = Dictionary(s.files.map { ($0.path, $0.edits) }, uniquingKeysWith: +)
            s.projectPath = ProjectResolver.resolve(cwd: s.cwd, touched: edits, prompts: s.prompts)
            return s
        }
    }

    /// session_index.jsonl 에 Codex 가 지어 준 스레드 이름이 있다.
    private func threadNames() -> [String: String] {
        var names: [String: String] = [:]
        _ = try? LineScanner.scan(path: root.appendingPathComponent("session_index.jsonl").path, from: 0) { line in
            guard let o = LineScanner.jsonObject(line), let id = o["id"] as? String, let name = o["thread_name"] as? String else { return }
            names[id] = name
        }
        return names
    }

    private func fillDetails(_ sessions: inout [String: WorkSession], warnings: inout [String]) {
        guard let path = latestDatabase(prefix: "thread_history"), let db = SQLiteReader(path: path) else {
            fillFromHistoryFile(&sessions)
            return
        }

        struct Detail {
            var prompts: [PromptEntry] = []
            var files: [String: Int] = [:]
            var tools: [String: Int] = [:]
            var added = 0
            var removed = 0
            var clock = ActiveClock()
            /// 항목(요청·생각·명령·답변…)이 이어진 구간. 한 차례 작업의 길이가 원본의 걸린 시간(`task_complete`)과 거의 같다.
            var spans: [WorkSpan] = []
            var skills: [String: Int] = [:]
        }
        var details: [String: Detail] = [:]
        do {
            try db.query("SELECT thread_id, created_at_ms, item_type, item_json FROM thread_items ORDER BY thread_id, rollout_ordinal") { row in
                guard let tid = row.string(0), sessions[tid] != nil, let type = row.string(2) else { return }
                let date = Date(timeIntervalSince1970: Double(row.int(1)) / 1000)
                var d = details[tid] ?? Detail()
                d.clock.tick(date)
                d.spans.extend(to: date)
                defer { details[tid] = d }
                guard type != "reasoning", let json = row.string(3),
                      let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return }

                switch type {
                case "userMessage":
                    let text = ((o["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
                    let cleaned = CodexText.clean(text)
                    if !cleaned.isEmpty {
                        let auto = sessions[tid]?.prompts.first?.isAutomated ?? false
                        d.prompts.append(PromptEntry(date: date, text: cleaned.clipped(ClaudeAccumulator.promptLimit), isAutomated: auto))
                    }
                case "agentMessage":
                    if let text = o["text"] as? String, !d.prompts.isEmpty {
                        let isFinal = (o["phase"] as? String) == "final_answer"
                        if isFinal || d.prompts[d.prompts.count - 1].reply == nil {
                            d.prompts[d.prompts.count - 1].reply = text.clipped(ClaudeAccumulator.replyLimit)
                        }
                    }
                case "fileChange":
                    for change in (o["changes"] as? [[String: Any]]) ?? [] {
                        guard let p = change["path"] as? String, !ClaudeAccumulator.isScratch(p) else { continue }
                        d.files[p, default: 0] += 1
                        let kind = (change["kind"] as? [String: Any])?["type"] as? String
                        let diff = (change["diff"] as? String) ?? ""
                        let counted = CodexText.countDiff(diff, isNewFile: kind == "add")
                        d.added += counted.added
                        d.removed += counted.removed
                        if !d.prompts.isEmpty { d.prompts[d.prompts.count - 1].noteEdit(p, added: counted.added, removed: counted.removed) }
                    }
                    d.tools["파일 수정", default: 0] += 1
                case "commandExecution":
                    d.tools["명령 실행", default: 0] += 1
                    // Codex 는 스킬을 쓸 때 <skills>/<이름>/SKILL.md 를 읽는다.
                    for action in (o["commandActions"] as? [[String: Any]]) ?? [] {
                        guard let path = action["path"] as? String, path.hasSuffix("/SKILL.md"), path.contains("/skills/") else { continue }
                        let name = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
                        d.skills[name, default: 0] += 1
                    }
                case "webSearch": d.tools["웹 검색", default: 0] += 1
                case "imageGeneration": d.tools["이미지 생성", default: 0] += 1
                case "imageView": d.tools["이미지 보기", default: 0] += 1
                case "mcpToolCall":
                    let server = (o["server"] as? String) ?? "도구"
                    d.tools["MCP · \(server)", default: 0] += 1
                default: break
                }
            }
        } catch {
            warnings.append(L("Codex 대화 내용을 읽지 못했습니다: %@", "\(error)"))
        }

        for (tid, d) in details {
            guard var s = sessions[tid] else { continue }
            if !d.prompts.isEmpty { s.prompts = d.prompts; s.hasTranscript = true }
            s.files = d.files.map { FileTouch(path: $0.key, edits: $0.value) }.sorted { $0.edits > $1.edits }
            s.toolUses = d.tools
            s.skillsUsed = d.skills
            s.linesAdded = d.added
            s.linesRemoved = d.removed
            if let first = d.clock.first, let last = d.clock.last {
                s.start = min(s.start, first)
                s.end = max(s.end, last)
                s.spans = d.spans
            }
            sessions[tid] = s
        }
        fillFromHistoryFile(&sessions)
    }

    /// 대화 DB 에 없는 스레드는 history.jsonl 의 입력 기록으로 채운다.
    private func fillFromHistoryFile(_ sessions: inout [String: WorkSession]) {
        var extra: [String: [PromptEntry]] = [:]
        _ = try? LineScanner.scan(path: root.appendingPathComponent("history.jsonl").path, from: 0) { line in
            guard let o = LineScanner.jsonObject(line), let sid = o["session_id"] as? String,
                  let text = o["text"] as? String, let ts = o["ts"] as? Double else { return }
            extra[sid, default: []].append(PromptEntry(date: Date(timeIntervalSince1970: ts), text: text.clipped(ClaudeAccumulator.promptLimit)))
        }
        for (sid, prompts) in extra {
            guard var s = sessions[sid], !s.hasTranscript, prompts.count > s.prompts.count else { continue }
            s.prompts = prompts.sorted { $0.date < $1.date }
            sessions[sid] = s
        }
    }
}

enum CodexText {
    static func title(_ raw: String) -> String {
        let t = clean(raw).singleLine
        return t.clipped(80)
    }

    /// ChatGPT 에서 넘겨받은 대화는 앞에 긴 머리말이 붙는다.
    static func clean(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("## Referenced ChatGPT conversation") else { return t }
        guard let range = t.range(of: "## My request:") else { return "ChatGPT 대화 이어받기" }
        var request = String(t[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        // "Continuing from [제목](chatgpt-conversation://...): 요청" → "(ChatGPT 「제목」 이어서) 요청"
        if let link = request.range(of: #"^Continuing from \[([^\]]*)\]\([^)]*\):?\s*"#, options: .regularExpression) {
            let head = String(request[link])
            let name = ClaudeText.between(head, "[", "]") ?? ""
            request = "(ChatGPT 「\(name)」 이어서) " + request[link.upperBound...]
        }
        return request
    }

    static func countDiff(_ diff: String, isNewFile: Bool) -> (added: Int, removed: Int) {
        if isNewFile { return (diff.isEmpty ? 0 : diff.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }, 0) }
        var added = 0
        var removed = 0
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("+++") || line.hasPrefix("---") { continue }
            if line.hasPrefix("+") { added += 1 } else if line.hasPrefix("-") { removed += 1 }
        }
        return (added, removed)
    }
}
