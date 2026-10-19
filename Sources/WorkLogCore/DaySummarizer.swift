import Foundation

/// AI 가 쓴 "이날 이 프로젝트에서 한 일" 요약.
public struct DaySummary: Hashable, Sendable {
    public var project: String
    /// yyyy-MM-dd
    public var day: String
    /// 요약 재료의 지문. 그날 요청·결과가 바뀌면 달라져서 다시 요약할 때를 안다.
    public var digest: String
    /// 요약한 도구 이름 ("Claude Code")
    public var engine: String
    public var headline: String
    public var points: [String]
    /// 요약에 넣은 요청 수.
    public var promptCount: Int
    /// 요약에 담은 마지막 요청 시각. 그 뒤 요청만 더해 이어 쓸 때 쓴다 (예전 요약은 없음).
    public var coveredUntil: Date?
    public var created: Date

    public init(project: String, day: String, digest: String, engine: String, headline: String, points: [String],
                promptCount: Int, coveredUntil: Date? = nil, created: Date = Date()) {
        self.project = project
        self.day = day
        self.digest = digest
        self.engine = engine
        self.headline = headline
        self.points = points
        self.promptCount = promptCount
        self.coveredUntil = coveredUntil
        self.created = created
    }

    public var key: String { Self.key(project: project, day: day) }
    public static func key(project: String, day: String) -> String { project + "|" + day }
}

/// 요약을 맡길 수 있는 AI 도구. 이 맥에 깔려 있는 것만 찾는다.
public struct SummaryEngine: Hashable, Sendable, Identifiable {
    public enum Kind: String, CaseIterable, Sendable, Identifiable {
        case claudeCode, codex, lmStudio
        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .claudeCode: return "Claude Code"
            case .codex: return "Codex"
            case .lmStudio: return "LM Studio"
            }
        }

        public var tool: AITool {
            switch self {
            case .claudeCode: return .claudeCode
            case .codex: return .codex
            case .lmStudio: return .lmStudio
            }
        }
    }

    public var kind: Kind
    /// claude·codex 는 실행 파일 경로, LM Studio 는 서버 주소.
    public var location: String
    /// LM Studio 에서 쓸 모델.
    public var model: String?
    /// 앱을 Finder 에서 띄우면 터미널의 PATH 가 없어서, 찾을 때 알아 둔 PATH 로 실행한다.
    var searchPath: String

    public var id: String { kind.rawValue }
    public var displayName: String { kind.displayName }

    /// 요약 재료가 어디로 가는지 (설명용).
    public var destination: String {
        switch kind {
        case .claudeCode: return L("Anthropic 서버(Claude Code)")
        case .codex: return L("OpenAI 서버(Codex)")
        case .lmStudio: return L("내 맥의 LM Studio") + (model.map { "(\($0))" } ?? "")
        }
    }
}

public struct SummaryError: Error, CustomStringConvertible, Sendable {
    public var description: String
    init(_ description: String) { self.description = description }
}

/// 하루치 작업 기록을 AI 에게 맡겨 "결국 무엇을 했는지" 몇 줄로 줄인다.
///
/// - Claude Code: `claude -p` (빠른 haiku 모델, 도구·MCP·훅 끄고, 세션을 남기지 않음)
/// - Codex: `codex exec --ephemeral` (읽기 전용, 생각 짧게, 스레드를 남기지 않음)
/// - LM Studio: 켜져 있는 로컬 서버 (내 맥 밖으로 나가지 않음)
///
/// 요약하러 부른 대화가 다시 작업 기록에 섞이지 않도록 기록을 남기지 않는 방식으로만 부른다.
public enum DaySummarizer {
    /// 요약 지시문이 바뀌면 올린다. 지문이 달라져 예전 요약을 다시 만든다.
    static let promptVersion = 3
    /// 재료 전체 글자 수 상한. 넘으면 요청·결과를 더 짧게 자른다.
    static let materialBudget = 9_000

    static func systemPrompt(_ language: AppLanguage) -> String {
        let name = language == .ko ? "한국어" : language == .en ? "영어(English)" : "일본어(日本語)"
        return "너는 개발 작업 기록을 읽고 그날 한 일을 짧게 정리하는 도우미다. 도구를 쓰거나 파일을 읽지 말고, 요청받은 형식의 요약만 \(name)로 출력한다."
    }

    /// 화면 언어가 한국어가 아니면 지시문 끝에 붙여 그 언어로 쓰게 한다. 형식(첫 줄 + "- " 목록)은 그대로.
    static func languageRule(_ language: AppLanguage) -> String {
        switch language {
        case .ko: return ""
        case .en: return "\n\n출력 언어: 영어(English). 위 형식은 그대로 지키되, 각 줄은 \"Added …\", \"Fixed …\" 처럼 짧은 영어 구로 쓰고, 남은 일은 \"- To do: …\" 로 쓴다."
        case .ja: return "\n\n出力言語: 日本語。上の形式はそのまま守り、各行は「〜を追加」「〜を修正」のように体言止めで短く書き、残りの作業は「- 残り: …」と書く。"
        }
    }

    static let instructions = """
        위는 한 사람이 AI 코딩 도구와 함께 이날 이 프로젝트에서 한 작업 기록이다. (요청 = 사람이 AI 에게 시킨 일, 결과 = AI 의 마지막 답)
        이날 결국 무엇을 했는지 한국어로 요약해라.

        """ + formatRules

    /// 이어 쓰기: 아까 만든 요약에 그 뒤 기록만 더해 하루 전체 요약을 다시 쓰게 한다 (보내는 글이 짧아진다).
    static let updateInstructions = """
        위 "지금까지 요약"은 이날 앞부분 작업을 정리한 것이고, "그 뒤 새 기록"은 그다음에 한 작업이다. (요청 = 사람이 AI 에게 시킨 일, 결과 = AI 의 마지막 답)
        둘을 합쳐 이날 전체 요약을 한국어로 새로 써라. 앞부분 내용도 빠뜨리지 말고, 겹치는 것은 한 줄로 합친다.
        "남은 일"이 새 기록에서 끝났으면 남은 일에서 뺀다.

        """ + formatRules

    static let formatRules = """
        형식:
        첫 줄: 이날 한 일을 한 줄로 (35자 이내, 마침표 없이)
        둘째 줄부터: "- " 로 시작하는 핵심 결과 2~5줄 (한 줄에 50자 이내)

        규칙:
        - 요청을 옮겨 적지 말고 만든 것, 고친 것, 정한 것 위주로 쓴다
        - 프로젝트 이름과 날짜는 이미 화면에 있으니 쓰지 않는다
        - 요청이 한두 개뿐인 날은 핵심 결과도 1~3줄로 줄인다
        - 비슷한 요청은 한 줄로 묶고, 커밋 번호·포트·pid 같은 자잘한 값은 뺀다
        - 모든 줄은 "…추가", "…고침", "…정리함" 처럼 명사형이나 "-함" 으로 짧게 끝낸다
        - 끝내지 못했거나 막힌 일이 있으면 마지막 줄을 "- 남은 일: …" 로 쓴다
        - 기록에 없는 내용은 지어내지 않는다
        - 머리말, 맺음말, 제목, 마크다운 강조 없이 위 형식만 출력한다
        """

    // MARK: - 재료

    /// 그날 요청 → 결과 → 고친 파일을 시간순으로 적은 글. 사람이 보낸 요청이 없으면 nil.
    /// `after` 를 주면 그 시각 뒤 요청만 (이어 쓰기용).
    public static func material(for day: DayGroup, projectName: String, after: Date? = nil) -> String? {
        let entries = day.entries.sorted { $0.firstDate < $1.firstDate }
        func included(_ p: PromptEntry) -> Bool { isAsked(p) && after.map { p.date > $0 } ?? true }
        let asked = entries.reduce(0) { $0 + $1.prompts.filter(included).count }
        guard asked > 0 else { return nil }
        // 요청이 많은 날은 하나하나를 짧게 잘라 전체 길이를 맞춘다.
        let each = max(60, min(400, materialBudget / (asked * 2)))

        var out = "프로젝트: \(projectName)\n날짜: \(Fmt.fullDay(day.day))\n"
        for entry in entries {
            let prompts = entry.prompts.filter(included)
            guard !prompts.isEmpty else { continue }
            out += "\n[세션] \(entry.session.title.singleLine.clipped(80)) (\(entry.session.tool.displayName))\n"
            for p in prompts {
                out += "- \(Fmt.time(p.date)) 요청: \(p.text.plainLine.clipped(each))\n"
                if let reply = p.reply, !reply.isEmpty {
                    out += "  결과: \(reply.outcomeLine.clipped(each))\n"
                }
                if !p.files.isEmpty {
                    let names = p.files.prefix(5).map { ($0 as NSString).lastPathComponent }
                    out += "  고친 파일: \(names.joined(separator: ", "))\(p.files.count > 5 ? " 외 \(p.files.count - 5)개" : "")\n"
                }
            }
        }
        return out
    }

    /// 요약할 하루치 기록: 그 프로젝트의 그날 세션 전부 (자동 실행 세션은 뺀다).
    /// 화면의 검색어·도구 거르기와 상관없이 같은 재료가 나와야 요약을 다시 쓸 수 있다.
    public static func source(project path: String, day: Date, sessions: [WorkSession]) -> DayGroup? {
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return nil }
        let mine = sessions.filter { $0.projectPath == path && !$0.isAutomated }
        return WorkLogAnalytics.days(WorkLogAnalytics.clip(mine, to: DateInterval(start: start, end: end))).first
    }

    /// 요약을 기다리는 지난 날짜들 (프로젝트 × 날짜, 최근 날부터): 요약이 없거나, 그날이 끝나기 전에 만든 요약이라 마감할 것.
    /// 오늘은 아직 끝나지 않아서 뺀다. `since` 를 주면 그날부터만.
    public static func backlog(sessions: [WorkSession], existing: [String: DaySummary], since: Date? = nil,
                               now: Date = Date()) -> [(project: String, day: Date, plan: Plan)] {
        let today = Calendar.current.startOfDay(for: now)
        let human = sessions.filter { !$0.isAutomated }
        var result: [(project: String, day: Date, plan: Plan)] = []
        for (path, list) in Dictionary(grouping: human, by: \.projectPath) {
            for day in WorkLogAnalytics.days(list) where day.day < today && day.day >= (since ?? .distantPast) {
                let plan = plan(for: day, existing: existing[DaySummary.key(project: path, day: Fmt.isoDay(day.day))], now: now)
                if plan != .keep { result.append((path, day.day, plan)) }
            }
        }
        return result.sorted { $0.day == $1.day ? $0.project < $1.project : $0.day > $1.day }
    }

    // MARK: - 언제 요약할지

    /// 오늘은 마지막 요청 뒤 이만큼 조용하면 "손을 뗐다"고 보고 그때 요약한다. 일하는 중에는 부르지 않는다.
    public static let idleGap: TimeInterval = 30 * 60

    public enum Plan: Equatable, Sendable {
        /// 그대로 둔다: 요약이 최신이거나, 끝난 날의 마감된 요약.
        case keep
        /// 처음부터 요약한다.
        case full
        /// 지난 요약에 `after` 뒤의 새 요청만 더해 고쳐 쓴다.
        case update(after: Date)
        /// 오늘 아직 일하는 중이라 이때까지 기다린다.
        case wait(until: Date)
    }

    /// 이날 요약을 어떻게 할지.
    /// - 지난 날: 요약이 없으면 처음부터. 그날이 끝나기 전에 만든 요약이면 남은 요청을 더해 한 번 마감하고, 그 뒤로는 그대로 둔다.
    /// - 오늘: 마지막 요청 뒤 30분이 지나야 요약하고, 요약이 있으면 그 뒤 요청만 더해 이어 쓴다.
    /// - `force`(버튼): 새 요청이 있으면 이어 쓰기, 없으면 처음부터 다시.
    public static func plan(for day: DayGroup, existing: DaySummary?, now: Date = Date(), force: Bool = false) -> Plan {
        let asked = askedPrompts(in: day)
        guard let last = asked.last?.date else { return .keep }
        let calendar = Calendar.current
        let isToday = calendar.isDate(day.day, inSameDayAs: now)
        let wake = last.addingTimeInterval(idleGap)
        guard let existing, let covered = covered(by: existing, asked: asked) else {
            return force || !isToday || wake <= now ? .full : .wait(until: wake)
        }
        let fresh = asked.filter { $0.date > covered }.count
        if force { return fresh > 0 ? .update(after: covered) : .full }
        guard fresh > 0 else { return .keep }
        if isToday { return wake <= now ? .update(after: covered) : .wait(until: wake) }
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day.day)) ?? now
        return existing.created < dayEnd ? .update(after: covered) : .keep
    }

    /// 요약한 뒤로 생긴 요청 수.
    public static func newSince(_ summary: DaySummary, in day: DayGroup) -> Int {
        let asked = askedPrompts(in: day)
        guard let covered = covered(by: summary, asked: asked) else { return asked.count }
        return asked.filter { $0.date > covered }.count
    }

    /// 그날 사람이 보낸 요청 (시간순).
    public static func askedPrompts(in day: DayGroup) -> [PromptEntry] {
        day.entries.flatMap { $0.prompts.filter(isAsked) }.sorted { $0.date < $1.date }
    }

    /// 요약이 어디까지 담았는지. 시각을 남기지 않은 예전 요약은 요청 수로 어림한다.
    static func covered(by summary: DaySummary, asked: [PromptEntry]) -> Date? {
        if let until = summary.coveredUntil { return until }
        guard summary.promptCount > 0, !asked.isEmpty else { return nil }
        return asked[min(summary.promptCount, asked.count) - 1].date
    }

    /// 요약에 넣을 요청: 사람이 직접 보낸 것만 (명령·자동 메시지는 뺀다).
    static func isAsked(_ p: PromptEntry) -> Bool { !p.isCommand && !p.isAutomated }

    public static func promptCount(for day: DayGroup) -> Int {
        day.entries.reduce(0) { $0 + $1.prompts.filter(isAsked).count }
    }

    /// 재료의 지문 (FNV-1a). Swift 의 hashValue 는 실행마다 달라서 직접 계산한다.
    public static func digest(_ material: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "v\(promptVersion)\n\(material)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    // MARK: - 결과 읽기

    /// AI 의 답에서 첫 줄 한 문장과 "- " 목록을 꺼낸다. 생각 과정·머리말·마크다운 강조는 걷어 낸다.
    public static func parse(_ raw: String) -> (headline: String, points: [String])? {
        var text = raw
        // LM Studio 의 생각하는 모델은 <think>…</think> 를 먼저 내보낸다.
        while let open = text.range(of: "<think>"), let close = text.range(of: "</think>", range: open.upperBound..<text.endIndex) {
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        if let close = text.range(of: "</think>") { text = String(text[close.upperBound...]) }

        var headline: String?
        var points: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            var t = line.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
            if t.isEmpty || t.hasPrefix("```") || t.allSatisfy({ "-=_*".contains($0) }) { continue }
            if let bullet = t.range(of: #"^([-•*·▪︎]|\d+[.)])\s+"#, options: .regularExpression) {
                let body = String(t[bullet.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !body.isEmpty { points.append(body) }
                continue
            }
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces))
            if let label = t.range(of: #"^(요약|한 줄 요약|한줄 요약|이날 한 일|오늘 한 일|Summary|要約)\s*[:：]\s*"#, options: [.regularExpression, .caseInsensitive]) {
                t.removeSubrange(label)
            }
            guard !t.isEmpty else { continue }
            if headline == nil { headline = t } else { points.append(t) }
        }
        if headline == nil, !points.isEmpty { headline = points.removeFirst() }
        guard var headline else { return nil }
        while let last = headline.last, ".。".contains(last) { headline.removeLast() }
        return (headline.clipped(140), points.prefix(6).map { $0.clipped(200) })
    }

    // MARK: - 요약하기

    /// 재료를 AI 에게 보내 요약을 받아 온다. `previous` 를 주면 그 요약에 `material`(그 뒤 기록)을 더해 이어 쓴다.
    public static func summarize(_ material: String, with engine: SummaryEngine, previous: DaySummary? = nil,
                                 language: AppLanguage = Loc.language,
                                 timeout: TimeInterval = 150) async throws -> (headline: String, points: [String]) {
        let prompt: String
        if let previous {
            let before = ([previous.headline] + previous.points.map { "- \($0)" }).joined(separator: "\n")
            prompt = "[지금까지 요약]\n\(before)\n\n[그 뒤 새 기록]\n\(material)\n---\n\(updateInstructions)" + languageRule(language)
        } else {
            prompt = material + "\n---\n" + instructions + languageRule(language)
        }
        let system = systemPrompt(language)
        let raw: String
        switch engine.kind {
        case .claudeCode: raw = try await runClaude(engine, prompt: prompt, system: system, timeout: timeout)
        case .codex: raw = try await runCodex(engine, prompt: prompt, timeout: timeout)
        case .lmStudio: raw = try await runLMStudio(engine, prompt: prompt, system: system, timeout: timeout)
        }
        guard let parsed = parse(raw) else {
            throw SummaryError(raw.isEmpty ? L("%@ 가 빈 답을 보냈어요", engine.displayName) : L("요약 형식을 알아보지 못했어요"))
        }
        return parsed
    }

    private static func runClaude(_ engine: SummaryEngine, prompt: String, system: String, timeout: TimeInterval) async throws -> String {
        let work = try workDirectory()
        let input = work.appendingPathComponent("\(UUID().uuidString).txt")
        try prompt.write(to: input, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: input) }
        let result = try await execute(engine.location, [
            "-p", "--model", "haiku", "--output-format", "text",
            // 이 요약 대화가 ~/.claude 에 새 세션으로 남지 않게.
            "--no-session-persistence",
            // 도구·MCP 서버·스킬·훅을 꺼서 빨리 뜨고 아무것도 건드리지 않게.
            "--tools", "", "--strict-mcp-config", "--disable-slash-commands",
            "--settings", #"{"disableAllHooks":true}"#,
            "--system-prompt", system,
        ], input: input, cwd: work, environment: environment(for: engine), timeout: timeout)
        try result.check(engine)
        return result.output
    }

    private static func runCodex(_ engine: SummaryEngine, prompt: String, timeout: TimeInterval) async throws -> String {
        let work = try workDirectory()
        let name = UUID().uuidString
        let input = work.appendingPathComponent("\(name).txt")
        let output = work.appendingPathComponent("\(name).out")
        try prompt.write(to: input, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }
        let result = try await execute(engine.location, [
            // --ephemeral: 이 요약 대화가 Codex 스레드 목록에 남지 않게.
            "exec", "--ephemeral", "--skip-git-repo-check", "-s", "read-only", "--color", "never",
            "-c", #"model_reasoning_effort="low""#,
            "-o", output.path, "-",
        ], input: input, cwd: work, environment: environment(for: engine), timeout: timeout)
        try result.check(engine)
        return (try? String(contentsOf: output, encoding: .utf8)) ?? result.output
    }

    private static func runLMStudio(_ engine: SummaryEngine, prompt: String, system: String, timeout: TimeInterval) async throws -> String {
        guard let url = URL(string: engine.location + "/v1/chat/completions") else { throw SummaryError(L("LM Studio 주소가 이상해요")) }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": engine.model ?? "",
            "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
            "temperature": 0.2,
            "max_tokens": 1_200,
            "stream": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw SummaryError(L("LM Studio 서버에 닿지 않아요. LM Studio 에서 서버를 켜 주세요"))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SummaryError(L("LM Studio 답을 읽지 못했어요")) }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String { throw SummaryError("LM Studio: \(message.clipped(120))") }
        if let message = json["error"] as? String { throw SummaryError("LM Studio: \(message.clipped(120))") }
        let choice = (json["choices"] as? [[String: Any]])?.first
        return ((choice?["message"] as? [String: Any])?["content"] as? String) ?? ""
    }

    /// 요약할 때 쓰는 임시 폴더. 어느 프로젝트에도 속하지 않아 그 폴더의 규칙 파일을 읽지 않는다.
    static func workDirectory() throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("AIWorkLog-summary", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // 요약 도중 앱을 끄면 재료 파일이 남는다. 오래된 것은 지운다.
        let old = Date().addingTimeInterval(-15 * 60)
        for file in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified < old {
                try? fm.removeItem(at: file)
            }
        }
        return dir
    }

    // MARK: - 도구 찾기

    /// 이 맥에서 요약에 쓸 수 있는 AI 를 찾는다. 터미널 설정을 읽느라 1초쯤 걸릴 수 있어 메인 스레드 밖에서 부른다.
    public static func detectEngines() async -> [SummaryEngine] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let shell = await shellLookup()
        let searchPath = shell.path ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        let fm = FileManager.default

        func find(_ name: String, _ candidates: [String]) -> String? {
            let fromShell = shell.commands[name].map { [$0] } ?? []
            let fromPath = searchPath.split(separator: ":").map { "\($0)/\(name)" }
            return (fromShell + candidates + fromPath).first { fm.isExecutableFile(atPath: $0) }
        }

        var engines: [SummaryEngine] = []
        if let claude = find("claude", ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude",
                                        "/usr/local/bin/claude", "\(home)/.volta/bin/claude", "\(home)/.npm-global/bin/claude",
                                        "\(home)/.bun/bin/claude"]) {
            engines.append(SummaryEngine(kind: .claudeCode, location: claude, searchPath: searchPath))
        }
        if let codex = find("codex", ["\(home)/.volta/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                                      "\(home)/.local/bin/codex", "\(home)/.npm-global/bin/codex", "\(home)/.bun/bin/codex",
                                      "/Applications/Codex.app/Contents/Resources/codex"]) {
            engines.append(SummaryEngine(kind: .codex, location: codex, searchPath: searchPath))
        }
        if let lm = await lmStudioServer(home: home) {
            engines.append(lm)
        }
        return engines
    }

    /// 로그인 셸에게 claude·codex 위치와 PATH 를 물어본다 (Finder 에서 띄운 앱은 터미널 PATH 를 모른다).
    private static func shellLookup() async -> (commands: [String: String], path: String?) {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil } ?? "/bin/zsh"
        let script = #"printf '\n@@claude=%s\n@@codex=%s\n@@PATH=%s\n' "$(command -v claude)" "$(command -v codex)" "$PATH""#
        guard let result = try? await execute(shell, ["-ilc", script], input: nil, cwd: FileManager.default.homeDirectoryForCurrentUser,
                                              environment: ProcessInfo.processInfo.environment, timeout: 6) else { return ([:], nil) }
        var commands: [String: String] = [:]
        var path: String?
        for line in result.output.split(whereSeparator: \.isNewline) where line.hasPrefix("@@") {
            let parts = line.dropFirst(2).split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[0] == "PATH" { path = parts[1] }
            // alias 처럼 경로가 아닌 답은 버린다.
            else if parts[1].hasPrefix("/") { commands[parts[0]] = parts[1] }
        }
        return (commands, path)
    }

    /// LM Studio 서버가 켜져 있으면 올려 둔 모델(없으면 받아 둔 첫 모델)로 쓴다.
    private static func lmStudioServer(home: String) async -> SummaryEngine? {
        var port = 1234
        let config = URL(fileURLWithPath: "\(home)/.lmstudio/.internal/http-server-config.json")
        if let data = try? Data(contentsOf: config), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let p = json["port"] as? Int {
            port = p
        }
        let base = "http://127.0.0.1:\(port)"
        guard let url = URL(string: base + "/api/v0/models") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 1.5)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else { return nil }
        let chat = models.filter { ["llm", "vlm"].contains($0["type"] as? String ?? "llm") }
        let pick = chat.first { ($0["state"] as? String) == "loaded" } ?? chat.first
        guard let id = pick?["id"] as? String else { return nil }
        return SummaryEngine(kind: .lmStudio, location: base, model: id, searchPath: "")
    }

    // MARK: - 실행

    static func environment(for engine: SummaryEngine) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Claude Code 안에서 띄운 경우에 붙는 표시. 남아 있으면 claude 가 다른 세션 안이라고 여긴다.
        for key in ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT"] { env.removeValue(forKey: key) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // 한 식으로 이으면 오래된 컴파일러(Swift 6.2)가 타입을 못 정해서 나눠 쓴다.
        let common: [String] = ["\(home)/.local/bin", "\(home)/.volta/bin", "/opt/homebrew/bin", "/usr/local/bin",
                                "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var candidates: [String] = [(engine.location as NSString).deletingLastPathComponent]
        candidates += engine.searchPath.split(separator: ":").map(String.init)
        candidates += (env["PATH"] ?? "").split(separator: ":").map(String.init)
        candidates += common
        var seen = Set<String>()
        let dirs = candidates.filter { !$0.isEmpty && seen.insert($0).inserted }
        env["PATH"] = dirs.joined(separator: ":")
        // volta 로 깐 codex 는 VOLTA_HOME 이 있어야 실행된다.
        if env["VOLTA_HOME"] == nil, FileManager.default.fileExists(atPath: "\(home)/.volta") { env["VOLTA_HOME"] = "\(home)/.volta" }
        env["NO_COLOR"] = "1"
        return env
    }

    struct ProcessResult {
        var status: Int32
        var output: String
        var error: String
        var timedOut: Bool

        func check(_ engine: SummaryEngine) throws {
            if timedOut { throw SummaryError(L("%@ 가 너무 오래 걸려서 멈췄어요", engine.displayName)) }
            guard status == 0 else {
                let detail = (error + "\n" + output).split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty } ?? "종료 코드 \(status)"
                throw SummaryError("\(engine.displayName): \(detail.clipped(140))")
            }
        }
    }

    /// 프로그램을 실행하고 끝날 때까지 기다린다. `timeout` 이 지나면 멈춘다.
    /// 자식 프로세스가 출력 파이프를 붙들고 있어도 멈추지 않게, 끝날 때까지 모인 출력만 쓴다.
    static func execute(_ executable: String, _ arguments: [String], input: URL?, cwd: URL,
                        environment: [String: String], timeout: TimeInterval) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = cwd
            process.environment = environment
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = input.flatMap { try? FileHandle(forReadingFrom: $0) } ?? FileHandle.nullDevice
            let outData = Collected(), errData = Collected()
            out.fileHandleForReading.readabilityHandler = { outData.append($0.availableData) }
            err.fileHandleForReading.readabilityHandler = { errData.append($0.availableData) }
            process.terminationHandler = { p in
                // 마지막으로 남은 출력이 들어올 틈을 조금 준다.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                    out.fileHandleForReading.readabilityHandler = nil
                    err.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(returning: ProcessResult(
                        status: p.terminationStatus,
                        output: String(decoding: outData.value, as: UTF8.self),
                        error: String(decoding: errData.value, as: UTF8.self),
                        timedOut: p.terminationReason == .uncaughtSignal))
                }
            }
            do {
                try process.run()
            } catch {
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: SummaryError(L("%@ 를 실행하지 못했어요", (executable as NSString).lastPathComponent)))
                return
            }
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if process.isRunning { kill(pid, SIGKILL) } }
            }
        }
    }

    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            lock.lock(); data.append(chunk); lock.unlock()
        }
        var value: Data { lock.lock(); defer { lock.unlock() }; return data }
    }
}
