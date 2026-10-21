import Foundation

/// Claude Code 대화 기록(~/.claude/projects/*/*.jsonl) 한 파일을 읽어 가며 쌓는 상태.
/// 기록 파일은 뒤에 덧붙기만 하므로, 이 상태를 캐시에 두고 늘어난 부분만 이어 읽는다.
struct ClaudeAccumulator: Codable, Hashable {
    struct CostPart: Codable, Hashable {
        var costUSD: Double
        var linesAdded: Int
        var linesRemoved: Int
        var models: [String: ModelUsage]
    }

    /// 해석 규칙이 바뀌면 올린다. 보관함에 남은 읽기 위치의 번호가 다르면 원본을 처음부터 다시 읽는다.
    static let parserVersion = 4
    var version = ClaudeAccumulator.parserVersion
    var sessionId: String
    var customTitle: String?
    var aiTitle: String?
    var summaryTitle: String?
    var cwd: String?
    var gitBranch: String?
    var clock = ActiveClock()
    var prompts: [PromptEntry] = []
    /// 요청 없이 시작된 세션(예약 작업 등)의 마지막 답변.
    var orphanReply: String?
    var fileEdits: [String: Int] = [:]
    var toolUses: [String: Int] = [:]
    var models: [String: ModelUsage] = [:]
    var lastMessageId: String?
    var approxAdded = 0
    var approxRemoved = 0
    var automated = false
    /// 이 세션을 띄운 곳 (`cli` = 터미널, `sdk-cli` = `claude -p`, `sdk-ts`·`sdk-py` = Agent SDK 로 만든 앱).
    var entrypoint: String?
    var skillsUsed: [String: Int] = [:]
    /// 프로세스(시작 시각)마다 비용이 0부터 다시 쌓이므로 시작 시각별 마지막 값을 둔다.
    var costParts: [String: CostPart] = [:]

    /// 보관함에 읽기 상태를 남길 때 요청 목록(`prompts`)은 뺀다. 요청은 보관함의 prompts 표에 이미 있어서,
    /// 이어 읽을 때 거기서 다시 채운다 (`resumed(withArchived:)`). 같은 내용을 두 번 저장하지 않으려는 것.
    enum CodingKeys: String, CodingKey {
        case version, sessionId, customTitle, aiTitle, summaryTitle, cwd, gitBranch, clock, orphanReply, fileEdits,
             toolUses, models, lastMessageId, approxAdded, approxRemoved, automated, entrypoint, skillsUsed, costParts
    }

    static let orphanPlaceholder = "(요청 없이 시작된 세션)"

    /// 저장해 둔 읽기 상태에 보관된 요청 목록을 되돌려 놓는다. 보관본이 없으면 nil (처음부터 다시 읽어야 함).
    func resumed(withArchived session: WorkSession?) -> ClaudeAccumulator? {
        guard let session else { return nil }
        var acc = self
        // 요청 없는 세션에 보여 주려고 붙인 자리표시는 실제 요청이 아니다.
        acc.prompts = session.prompts.filter { !($0.text == Self.orphanPlaceholder && $0.isAutomated) }
        return acc
    }

    init(sessionId: String) {
        self.sessionId = sessionId
    }

    /// 보관함에 온전히 남기려고 넉넉히 둔다. 이보다 긴 글만 잘린다.
    static let replyLimit = 20_000
    static let promptLimit = 20_000
    static let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]

    mutating func ingest(_ o: [String: Any]) {
        guard let type = o["type"] as? String else { return }
        switch type {
        case "user": ingestUser(o)
        case "assistant": ingestAssistant(o)
        case "ai-title": aiTitle = (o["aiTitle"] as? String) ?? aiTitle
        case "custom-title": customTitle = (o["customTitle"] as? String) ?? customTitle
        case "summary": if summaryTitle == nil { summaryTitle = o["summary"] as? String }
        case "cost-state": ingestCost(o)
        case "attachment": ingestQueued(o)
        default: break
        }
    }

    private mutating func noteContext(_ o: [String: Any]) {
        if cwd == nil, let c = o["cwd"] as? String, !c.isEmpty { cwd = c }
        if let b = o["gitBranch"] as? String, !b.isEmpty, b != "HEAD" { gitBranch = b }
        if let e = o["entrypoint"] as? String, !e.isEmpty {
            if entrypoint == nil { entrypoint = e }
            // `claude -p` 는 스크립트나 다른 앱의 보조 호출(대화 제목·브랜치 이름 짓기 등)이라 세션째 자동으로 본다.
            if e == "sdk-cli" { automated = true }
        }
        if let ts = o["timestamp"] as? String, let d = FastDate.parse(ts) { clock.tick(d) }
    }

    private mutating func ingestUser(_ o: [String: Any]) {
        if (o["isSidechain"] as? Bool) == true { return }
        noteContext(o)
        if o["toolUseResult"] != nil || (o["isMeta"] as? Bool) == true { return }
        guard let message = o["message"] as? [String: Any] else { return }

        var text = ""
        var images = 0
        if let s = message["content"] as? String {
            text = s
        } else if let items = message["content"] as? [[String: Any]] {
            for item in items {
                switch item["type"] as? String {
                case "tool_result": return
                case "text": text += (text.isEmpty ? "" : "\n") + ((item["text"] as? String) ?? "")
                case "image": images += 1
                default: break
                }
            }
        }

        let date = (o["timestamp"] as? String).flatMap(FastDate.parse) ?? clock.last ?? Date()
        if let command = ClaudeText.command(in: text) {
            if !ClaudeText.builtinCommands.contains(command.name) { skillsUsed[command.name, default: 0] += 1 }
            // 인자 없는 /login, /status 같은 건 작업 기록으로서 의미가 없어서 뺀다.
            if !command.args.isEmpty {
                prompts.append(PromptEntry(date: date, text: "/\(command.name) \(command.args)".clipped(ClaudeAccumulator.promptLimit), isCommand: true))
            }
            return
        }

        if let origin = o["origin"] as? [String: Any] {
            guard (origin["kind"] as? String) == "human" else { return }
        } else {
            if (o["promptSource"] as? String) == "system" { return }
            if ClaudeText.isMachineText(text) { return }
        }

        var cleaned = ClaudeText.clean(text)
        if cleaned.isEmpty && images > 0 { cleaned = "[이미지 \(images)장]" }
        guard !cleaned.isEmpty else { return }
        // Agent SDK 로 Claude Code 를 품은 앱(데스크톱 GUI 등)은 사람이 그 앱에 쓴 글도 promptSource "sdk" 로 남긴다.
        // 그런 앱에서는 사람 요청으로 세고, 터미널 세션에 프로그램이 끼워 넣은 글만 자동으로 본다.
        let isAuto = automated || ((o["promptSource"] as? String) == "sdk" && !isAgentSDK)
        prompts.append(PromptEntry(date: date, text: cleaned.clipped(ClaudeAccumulator.promptLimit), isAutomated: isAuto))
    }

    /// AI 가 일하는 도중에 내가 보낸 메시지는 user 줄이 아니라 queued_command 첨부로 남는다.
    private mutating func ingestQueued(_ o: [String: Any]) {
        guard (o["isSidechain"] as? Bool) != true,
              let a = o["attachment"] as? [String: Any], (a["type"] as? String) == "queued_command",
              ((a["origin"] as? [String: Any])?["kind"] as? String) == "human",
              let text = a["prompt"] as? String else { return }
        noteContext(o)
        let cleaned = ClaudeText.clean(text)
        guard !cleaned.isEmpty else { return }
        let date = (o["timestamp"] as? String).flatMap(FastDate.parse) ?? clock.last ?? Date()
        prompts.append(PromptEntry(date: date, text: cleaned.clipped(ClaudeAccumulator.promptLimit), isAutomated: automated))
    }

    /// Agent SDK(sdk-ts, sdk-py …)로 띄운 세션. `sdk-cli`(`claude -p`)는 뺀다.
    var isAgentSDK: Bool { entrypoint.map { $0.hasPrefix("sdk-") && $0 != "sdk-cli" } ?? false }

    private mutating func ingestAssistant(_ o: [String: Any]) {
        if (o["isSidechain"] as? Bool) == true { return }
        noteContext(o)
        guard let message = o["message"] as? [String: Any] else { return }
        let model = (message["model"] as? String) ?? "unknown"

        // 한 답변이 여러 줄로 나뉘어 기록되고 줄마다 같은 사용량이 붙어 있어서, 메시지 id 가 바뀔 때만 센다.
        if let id = message["id"] as? String, id != lastMessageId, model != "<synthetic>" {
            lastMessageId = id
            if let usage = message["usage"] as? [String: Any] {
                var m = models[model] ?? ModelUsage()
                m.inputTokens += Self.int(usage["input_tokens"])
                m.outputTokens += Self.int(usage["output_tokens"])
                m.cacheReadTokens += Self.int(usage["cache_read_input_tokens"])
                m.cacheWriteTokens += Self.int(usage["cache_creation_input_tokens"])
                models[model] = m
            }
        }

        guard let items = message["content"] as? [[String: Any]] else { return }
        for item in items {
            switch item["type"] as? String {
            case "text":
                guard let t = item["text"] as? String else { continue }
                let reply = t.clipped(ClaudeAccumulator.replyLimit)
                guard !reply.isEmpty, reply != "No response requested." else { continue }
                if prompts.isEmpty { orphanReply = reply } else { prompts[prompts.count - 1].reply = reply }
            case "tool_use":
                guard let name = item["name"] as? String else { continue }
                toolUses[ToolNames.group(name), default: 0] += 1
                if name == "Skill", let skill = (item["input"] as? [String: Any])?["skill"] as? String {
                    skillsUsed[skill, default: 0] += 1
                }
                guard ClaudeAccumulator.editTools.contains(name), let input = item["input"] as? [String: Any] else { continue }
                guard let path = (input["file_path"] as? String) ?? (input["notebook_path"] as? String), !Self.isScratch(path) else { continue }
                fileEdits[path, default: 0] += 1
                let lines = Self.approximateLines(tool: name, input: input)
                approxAdded += lines.added
                approxRemoved += lines.removed
                if !prompts.isEmpty { prompts[prompts.count - 1].noteEdit(path, added: lines.added, removed: lines.removed) }
            default:
                break
            }
        }
    }

    /// 편집 내용의 줄 수로 늘고 준 줄을 어림한다. 바뀌지 않은 앞뒤 줄도 세지므로 실제보다 조금 많다.
    static func approximateLines(tool: String, input: [String: Any]) -> (added: Int, removed: Int) {
        func lines(_ any: Any?) -> Int {
            guard let s = any as? String, !s.isEmpty else { return 0 }
            return s.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        }
        switch tool {
        case "Write":
            return (lines(input["content"]), 0)
        case "Edit":
            return (lines(input["new_string"]), lines(input["old_string"]))
        case "MultiEdit":
            let edits = (input["edits"] as? [[String: Any]]) ?? []
            return (edits.reduce(0) { $0 + lines($1["new_string"]) }, edits.reduce(0) { $0 + lines($1["old_string"]) })
        default:
            return (0, 0)
        }
    }

    private mutating func ingestCost(_ o: [String: Any]) {
        let key = String(describing: o["startTime"] ?? "?")
        var models: [String: ModelUsage] = [:]
        for (name, value) in (o["modelUsage"] as? [String: [String: Any]]) ?? [:] {
            models[name] = ModelUsage(
                inputTokens: Self.int(value["inputTokens"]),
                outputTokens: Self.int(value["outputTokens"]),
                cacheReadTokens: Self.int(value["cacheReadInputTokens"]),
                cacheWriteTokens: Self.int(value["cacheCreationInputTokens"]),
                costUSD: value["costUSD"] as? Double
            )
        }
        costParts[key] = CostPart(
            costUSD: (o["totalCostUSD"] as? Double) ?? 0,
            linesAdded: Self.int(o["totalLinesAdded"]),
            linesRemoved: Self.int(o["totalLinesRemoved"]),
            models: models
        )
    }

    /// 세션마다 만들어지는 임시 작업 폴더의 파일은 작업 결과로 치지 않는다.
    static func isScratch(_ path: String) -> Bool {
        path.hasPrefix("/private/tmp/") || path.hasPrefix("/tmp/") || path.hasPrefix("/private/var/folders/")
    }

    static func int(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        return 0
    }

    func makeSession(sourcePath: String, subagents: Int) -> WorkSession? {
        guard let start = clock.first, let end = clock.last else { return nil }
        let realPrompts = prompts.filter { !$0.isCommand }
        let title = [customTitle, aiTitle, summaryTitle, realPrompts.first?.text, prompts.first?.text]
            .compactMap { $0?.singleLine.clipped(80) }
            .first { !$0.isEmpty } ?? "제목 없는 세션"
        let dir = cwd ?? ""

        var prompts = self.prompts
        if prompts.isEmpty, let orphanReply {
            prompts.append(PromptEntry(date: start, text: Self.orphanPlaceholder, isAutomated: true, reply: orphanReply))
        }

        var session = WorkSession(
            tool: .claudeCode,
            sessionId: sessionId,
            title: title,
            cwd: dir,
            projectPath: ProjectResolver.resolve(cwd: dir, touched: fileEdits, prompts: prompts),
            gitBranch: gitBranch,
            start: start,
            end: end,
            activeSeconds: clock.seconds,
            prompts: prompts,
            files: fileEdits.map { FileTouch(path: $0.key, edits: $0.value) }.sorted { $0.edits == $1.edits ? $0.path < $1.path : $0.edits > $1.edits },
            toolUses: toolUses,
            models: models,
            subagents: subagents,
            sourcePath: sourcePath,
            hasTranscript: true
        )
        session.skillsUsed = skillsUsed
        if !costParts.isEmpty {
            session.costUSD = costParts.values.reduce(0) { $0 + $1.costUSD }
            session.linesAdded = costParts.values.reduce(0) { $0 + $1.linesAdded }
            session.linesRemoved = costParts.values.reduce(0) { $0 + $1.linesRemoved }
            // 비용 기록에는 웹 검색 등 보조 모델까지 들어 있어 더 정확하다.
            var merged: [String: ModelUsage] = [:]
            for part in costParts.values {
                for (name, u) in part.models {
                    var m = merged[name] ?? ModelUsage(costUSD: 0)
                    m.inputTokens += u.inputTokens
                    m.outputTokens += u.outputTokens
                    m.cacheReadTokens += u.cacheReadTokens
                    m.cacheWriteTokens += u.cacheWriteTokens
                    m.costUSD = (m.costUSD ?? 0) + (u.costUSD ?? 0)
                    merged[name] = m
                }
            }
            if !merged.isEmpty { session.models = merged }
        }
        if session.linesAdded == nil || (session.linesAdded == 0 && approxAdded > 0) {
            session.linesAdded = approxAdded
            session.linesRemoved = approxRemoved
        }
        return session
    }
}

/// Claude Code 기록 안의 글에서 사람이 쓴 부분만 골라낸다.
enum ClaudeText {
    struct Command { var name: String; var args: String }

    /// Claude Code 에 원래 있는 명령. 내가 만든 스킬·명령과 구분하려고 둔다.
    static let builtinCommands: Set<String> = [
        "login", "logout", "status", "usage", "clear", "exit", "quit", "model", "config", "resume", "compact", "cost",
        "help", "mcp", "permissions", "memory", "doctor", "bug", "plugin", "plugins", "agents", "hooks", "ide",
        "terminal-setup", "vim", "theme", "fast", "effort", "rename", "export", "add-dir", "context", "rewind",
        "statusline", "upgrade", "release-notes", "privacy-settings", "feedback", "todos", "bashes", "tasks",
        "install-github-app", "output-style", "sandbox", "artifacts", "remote-control", "loop", "btw", "skills",
        "workflows", "fewer-permission-prompts", "extra-usage", "passes", "stats", "copy", "chrome", "desktop",
    ]

    static func command(in text: String) -> Command? {
        guard let name = between(text, "<command-name>", "</command-name>") else { return nil }
        let args = between(text, "<command-args>", "</command-args>") ?? ""
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return Command(name: trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed,
                       args: args.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 사람이 아니라 도구가 넣은 글인지 (예전 버전 기록에는 출처 표시가 없다).
    static func isMachineText(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        let prefixes = ["<local-command", "<bash-", "<task-notification", "<system-reminder", "<user-prompt-submit-hook",
                        "This session is being continued", "[Request interrupted", "Caveat:", "<command-message>"]
        return prefixes.contains { t.hasPrefix($0) }
    }

    static func clean(_ text: String) -> String {
        var t = text
        t = replaceBlocks(t, open: "<system-reminder>", close: "</system-reminder>") { _ in "" }
        // 붙여넣은 내용은 요청의 본문이라 남기고, 태그만 알아보기 쉬운 표시로 바꾼다.
        // 닫는 태그는 `</pasted_content id="b8ff">` 처럼 id 가 붙기도 한다.
        t = t.replacingOccurrences(of: #"<pasted_content[^>]*>"#, with: "\n〔붙여넣은 내용〕\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"</pasted_content[^>]*>"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func between(_ text: String, _ open: String, _ close: String) -> String? {
        guard let a = text.range(of: open), let b = text.range(of: close, range: a.upperBound..<text.endIndex) else { return nil }
        return String(text[a.upperBound..<b.lowerBound])
    }

    static func replaceBlocks(_ text: String, open: String, close: String, with replacement: (Substring) -> String) -> String {
        var result = ""
        var rest = text[...]
        while let a = rest.range(of: open) {
            result += rest[..<a.lowerBound]
            guard let b = rest.range(of: close, range: a.upperBound..<rest.endIndex) else {
                rest = rest[a.lowerBound...]
                break
            }
            result += replacement(rest[a.upperBound..<b.lowerBound])
            rest = rest[b.upperBound...]
        }
        return result + rest
    }
}

enum ToolNames {
    /// `mcp__playwright__browser_click` 처럼 긴 MCP 도구 이름은 서버 단위로 묶는다.
    static func group(_ name: String) -> String {
        let parts = name.components(separatedBy: "__")
        guard parts.count >= 3, parts[0] == "mcp" else { return name }
        var server = parts[1]
        if server.hasPrefix("claude_ai_") { server.removeFirst("claude_ai_".count) }
        return "MCP · \(server)"
    }
}

/// ~/.claude 아래 기록을 모두 읽는다.
public struct ClaudeCodeSource {
    public let root: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")) {
        self.root = root
    }

    var projectsDir: URL { root.appendingPathComponent("projects") }

    /// 대화 원본 파일 목록.
    func transcriptFiles() -> [URL] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) else { return [] }
        var files: [URL] = []
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            files += items.filter { $0.pathExtension == "jsonl" }
        }
        return files
    }

    func subagentCount(for transcript: URL) -> Int {
        let dir = transcript.deletingPathExtension().appendingPathComponent("subagents")
        let items = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return items.filter { $0.hasSuffix(".jsonl") }.count
    }

    /// 대화 원본이 지워진 세션도 ~/.claude/history.jsonl 에는 입력한 프롬프트가 남아 있다.
    func historySessions(excluding known: Set<String>) -> [WorkSession] {
        let path = root.appendingPathComponent("history.jsonl").path
        struct Bucket { var project: String; var prompts: [PromptEntry] = [] }
        var buckets: [String: Bucket] = [:]
        _ = try? LineScanner.scan(path: path, from: 0) { line in
            guard let o = LineScanner.jsonObject(line),
                  let sid = o["sessionId"] as? String, !known.contains(sid),
                  let display = o["display"] as? String,
                  let ms = o["timestamp"] as? Double else { return }
            let text = display.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let isCommand = text.hasPrefix("/") || text == "exit" || text == "quit"
            let date = Date(timeIntervalSince1970: ms / 1000)
            var bucket = buckets[sid] ?? Bucket(project: (o["project"] as? String) ?? "")
            bucket.prompts.append(PromptEntry(date: date, text: text.clipped(ClaudeAccumulator.promptLimit), isCommand: isCommand))
            buckets[sid] = bucket
        }

        return buckets.compactMap { sid, bucket in
            let prompts = bucket.prompts.sorted { $0.date < $1.date }
            let real = prompts.filter { !$0.isCommand }
            // /status, /usage 만 치고 나간 세션은 작업이 아니다.
            guard let first = real.first, let start = prompts.first?.date, let end = prompts.last?.date else { return nil }
            var clock = ActiveClock()
            for p in prompts { clock.tick(p.date) }
            return WorkSession(
                tool: .claudeCode,
                sessionId: sid,
                title: first.text.singleLine.clipped(80),
                cwd: bucket.project,
                projectPath: ProjectResolver.resolve(cwd: bucket.project, touched: [:], prompts: real),
                start: start,
                end: end,
                activeSeconds: clock.seconds,
                prompts: prompts.filter { !$0.isCommand || $0.text.contains(" ") },
                hasTranscript: false
            )
        }
    }

    /// Claude Code 가 프로젝트마다 남긴 memory/*.md 메모. 키는 원래 폴더 경로.
    func memoryNotes(knownPaths: Set<String>) -> [String: [MemoryNote]] {
        let fm = FileManager.default
        var byMangled: [String: String] = [:]
        for path in knownPaths { byMangled[Self.mangle(path)] = path }

        var result: [String: [MemoryNote]] = [:]
        guard let dirs = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) else { return [:] }
        for dir in dirs {
            let memDir = dir.appendingPathComponent("memory")
            guard let files = try? fm.contentsOfDirectory(at: memDir, includingPropertiesForKeys: [.contentModificationDateKey]),
                  let owner = byMangled[dir.lastPathComponent] else { continue }
            let notes = files
                .filter { $0.pathExtension == "md" && $0.lastPathComponent != "MEMORY.md" }
                .compactMap(MemoryNote.load)
                .sorted { $0.modified > $1.modified }
            if !notes.isEmpty { result[owner] = notes }
        }
        return result
    }

    /// Claude Code 가 폴더 경로로 기록 폴더 이름을 만드는 규칙 (영문·숫자 말고는 모두 '-').
    static func mangle(_ path: String) -> String {
        String(path.unicodeScalars.map { scalar -> Character in
            let v = scalar.value
            let isAlnum = (v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122)
            return isAlnum ? Character(scalar) : "-"
        })
    }
}

extension MemoryNote {
    static func load(_ url: URL) -> MemoryNote? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        var name = url.deletingPathExtension().lastPathComponent
        var summary = ""
        var kind: String?
        var body = text

        if text.hasPrefix("---"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) {
            let header = text[text.index(text.startIndex, offsetBy: 3)..<end.lowerBound]
            for raw in header.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces)
                func value(_ key: String) -> String? {
                    guard line.hasPrefix(key + ":") else { return nil }
                    return line.dropFirst(key.count + 1).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                }
                if let v = value("name") { name = v }
                if let v = value("description") { summary = v }
                if let v = value("type") { kind = v }
            }
            body = String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return MemoryNote(path: url.path, name: name, summary: summary, kind: kind, body: body, modified: modified)
    }
}
