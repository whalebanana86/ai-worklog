import Foundation

/// AI 작업 기록 보관함 (SQLite).
///
/// Claude Code 는 오래된 대화 원본을 스스로 지운다. 한 번 읽은 세션·요청·답변·고친 파일을 여기에 쌓아 두면
/// 원본이 사라져도 기록이 남고, 다음 실행부터는 원본을 다시 읽지 않고 여기서 바로 띄운다.
public final class WorkLogStore: @unchecked Sendable {
    public let url: URL
    private let db: SQLiteReader
    static let schemaVersion = 1

    /// 원본 기록 파일을 어디까지 읽었는지.
    struct SourceState {
        var size: Int
        var offset: Int
        var accumulator: ClaudeAccumulator
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AIWorkLog/worklog.sqlite")
    }

    public init(url: URL = WorkLogStore.defaultURL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try SQLiteReader(writablePath: url.path)
        // journal_size_limit: 정리한 뒤에도 쓰기 대기 파일(-wal)이 1MB 넘게 남지 않게.
        try db.exec("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA synchronous=NORMAL; PRAGMA journal_size_limit=1048576;")
        try migrate()
    }

    private func migrate() throws {
        try db.exec("""
            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
            CREATE TABLE IF NOT EXISTS sessions (
                key TEXT PRIMARY KEY,
                tool TEXT NOT NULL,
                session_id TEXT NOT NULL,
                title TEXT NOT NULL,
                cwd TEXT NOT NULL,
                project_path TEXT NOT NULL,
                git_branch TEXT,
                start REAL NOT NULL,
                end REAL NOT NULL,
                active_seconds REAL NOT NULL,
                cost_usd REAL,
                lines_added INTEGER,
                lines_removed INTEGER,
                subagents INTEGER NOT NULL DEFAULT 0,
                source_path TEXT,
                has_transcript INTEGER NOT NULL,
                source_missing INTEGER NOT NULL DEFAULT 0,
                tool_uses TEXT NOT NULL DEFAULT '{}',
                models TEXT NOT NULL DEFAULT '{}',
                files TEXT NOT NULL DEFAULT '[]',
                first_saved REAL NOT NULL,
                updated REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS prompts (
                session_key TEXT NOT NULL REFERENCES sessions(key) ON DELETE CASCADE,
                idx INTEGER NOT NULL,
                date REAL NOT NULL,
                text TEXT NOT NULL,
                reply TEXT,
                is_command INTEGER NOT NULL DEFAULT 0,
                is_automated INTEGER NOT NULL DEFAULT 0,
                files TEXT NOT NULL DEFAULT '[]',
                lines_added INTEGER NOT NULL DEFAULT 0,
                lines_removed INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (session_key, idx)
            );
            CREATE INDEX IF NOT EXISTS prompts_by_date ON prompts(date);
            CREATE INDEX IF NOT EXISTS sessions_by_end ON sessions(end);
            CREATE TABLE IF NOT EXISTS notes (
                path TEXT PRIMARY KEY,
                root TEXT NOT NULL,
                name TEXT NOT NULL,
                summary TEXT NOT NULL,
                kind TEXT,
                body TEXT NOT NULL,
                modified REAL NOT NULL,
                missing INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS sources (
                path TEXT PRIMARY KEY,
                size INTEGER NOT NULL,
                offset INTEGER NOT NULL,
                state BLOB NOT NULL,
                updated REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS day_summaries (
                project TEXT NOT NULL,
                day TEXT NOT NULL,
                digest TEXT NOT NULL,
                engine TEXT NOT NULL,
                headline TEXT NOT NULL,
                points TEXT NOT NULL DEFAULT '[]',
                prompt_count INTEGER NOT NULL DEFAULT 0,
                created REAL NOT NULL,
                PRIMARY KEY (project, day)
            );
            """)
        // 나중에 생긴 칸은 예전 보관함에 붙인다.
        if !db.hasColumn("sessions", "skills") {
            try db.exec("ALTER TABLE sessions ADD COLUMN skills TEXT NOT NULL DEFAULT '{}'")
        }
        if !db.hasColumn("day_summaries", "covered_until") {
            try db.exec("ALTER TABLE day_summaries ADD COLUMN covered_until REAL")
        }
        if !db.hasColumn("day_summaries", "edited") {
            try db.exec("""
                ALTER TABLE day_summaries ADD COLUMN edited INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE day_summaries ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE day_summaries ADD COLUMN previous TEXT;
                """)
        }
        try db.run("INSERT OR IGNORE INTO meta(key, value) VALUES ('schema', ?)", [String(Self.schemaVersion)])
        try db.run("INSERT OR IGNORE INTO meta(key, value) VALUES ('created', ?)", [String(Date().timeIntervalSince1970)])
    }

    // MARK: - 읽기

    public func loadSessions() throws -> [String: WorkSession] {
        var prompts: [String: [PromptEntry]] = [:]
        try db.query("SELECT session_key, date, text, reply, is_command, is_automated, files, lines_added, lines_removed FROM prompts ORDER BY session_key, idx") { row in
            guard let key = row.string(0) else { return }
            var p = PromptEntry(date: Date(timeIntervalSince1970: row.double(1)), text: row.string(2) ?? "",
                                isCommand: row.int(4) != 0, isAutomated: row.int(5) != 0, reply: row.string(3))
            p.files = Self.decode([String].self, row.string(6)) ?? []
            p.linesAdded = row.int(7)
            p.linesRemoved = row.int(8)
            prompts[key, default: []].append(p)
        }

        var sessions: [String: WorkSession] = [:]
        try db.query("""
            SELECT key, tool, session_id, title, cwd, project_path, git_branch, start, end, active_seconds, cost_usd,
                   lines_added, lines_removed, subagents, source_path, has_transcript, source_missing, tool_uses, models, files, skills
            FROM sessions
            """) { row in
            guard let key = row.string(0), let tool = row.string(1).flatMap(AITool.init(rawValue:)) else { return }
            var s = WorkSession(
                tool: tool,
                sessionId: row.string(2) ?? "",
                title: row.string(3) ?? "",
                cwd: row.string(4) ?? "",
                projectPath: row.string(5) ?? "",
                gitBranch: row.string(6),
                start: Date(timeIntervalSince1970: row.double(7)),
                end: Date(timeIntervalSince1970: row.double(8)),
                activeSeconds: row.double(9),
                prompts: prompts[key] ?? [],
                files: Self.decode([FileTouch].self, row.string(19)) ?? [],
                toolUses: Self.decode([String: Int].self, row.string(17)) ?? [:],
                models: Self.decode([String: ModelUsage].self, row.string(18)) ?? [:],
                costUSD: row.optionalDouble(10),
                linesAdded: row.optionalInt(11),
                linesRemoved: row.optionalInt(12),
                subagents: row.int(13),
                sourcePath: row.string(14),
                hasTranscript: row.int(15) != 0
            )
            s.sourceMissing = row.int(16) != 0
            s.skillsUsed = Self.decode([String: Int].self, row.string(20)) ?? [:]
            sessions[key] = s
        }
        return sessions
    }

    func loadSources() throws -> [String: SourceState] {
        var result: [String: SourceState] = [:]
        let decoder = PropertyListDecoder()
        try db.query("SELECT path, size, offset, state FROM sources") { row in
            guard let path = row.string(0), let data = row.data(3),
                  let acc = try? decoder.decode(ClaudeAccumulator.self, from: data) else { return }
            result[path] = SourceState(size: row.int(1), offset: row.int(2), accumulator: acc)
        }
        return result
    }

    public func loadNotes() throws -> [String: [MemoryNote]] {
        var result: [String: [MemoryNote]] = [:]
        try db.query("SELECT path, root, name, summary, kind, body, modified FROM notes ORDER BY modified DESC") { row in
            guard let path = row.string(0), let root = row.string(1) else { return }
            result[root, default: []].append(MemoryNote(path: path, name: row.string(2) ?? "", summary: row.string(3) ?? "",
                                                         kind: row.string(4), body: row.string(5) ?? "",
                                                         modified: Date(timeIntervalSince1970: row.double(6))))
        }
        return result
    }

    /// AI 가 쓴 날짜별 요약. 열쇠는 `DaySummary.key`.
    public func loadSummaries() throws -> [String: DaySummary] {
        var result: [String: DaySummary] = [:]
        try db.query("""
            SELECT project, day, digest, engine, headline, points, prompt_count, created, covered_until, edited, pinned, previous
            FROM day_summaries
            """) { row in
            guard let project = row.string(0), let day = row.string(1) else { return }
            let summary = DaySummary(project: project, day: day, digest: row.string(2) ?? "", engine: row.string(3) ?? "",
                                     headline: row.string(4) ?? "", points: Self.decode([String].self, row.string(5)) ?? [],
                                     promptCount: row.int(6), coveredUntil: row.optionalDouble(8).map(Date.init(timeIntervalSince1970:)),
                                     created: Date(timeIntervalSince1970: row.double(7)),
                                     edited: row.int(9) != 0, pinned: row.int(10) != 0,
                                     previous: Self.decode(DaySummary.Version.self, row.string(11)))
            result[summary.key] = summary
        }
        return result
    }

    // MARK: - 쓰기

    /// 요약을 저장한다. 되돌리기용 전 판을 정하지 않았으면, 지금 저장돼 있던 것을 전 판으로 남긴다 (터미널에서 만든 요약도).
    public func saveSummary(_ s: DaySummary) throws {
        var s = s
        if s.previous == nil, let old = try loadSummary(project: s.project, day: s.day) { s = s.replacing(old) }
        try db.run("""
            INSERT OR REPLACE INTO day_summaries
                (project, day, digest, engine, headline, points, prompt_count, created, covered_until, edited, pinned, previous)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [s.project, s.day, s.digest, s.engine, s.headline, Self.encode(s.points), s.promptCount, s.created, s.coveredUntil,
                  s.edited, s.pinned, s.previous.map { Self.encode($0) }])
    }

    private func loadSummary(project: String, day: String) throws -> DaySummary? {
        var found: DaySummary?
        try db.query("""
            SELECT digest, engine, headline, points, prompt_count, created, covered_until, edited FROM day_summaries
            WHERE project = ? AND day = ?
            """, [project, day]) { row in
            found = DaySummary(project: project, day: day, digest: row.string(0) ?? "", engine: row.string(1) ?? "",
                               headline: row.string(2) ?? "", points: Self.decode([String].self, row.string(3)) ?? [],
                               promptCount: row.int(4), coveredUntil: row.optionalDouble(6).map(Date.init(timeIntervalSince1970:)),
                               created: Date(timeIntervalSince1970: row.double(5)), edited: row.int(7) != 0)
        }
        return found
    }

    /// 바뀐 세션·읽은 위치·메모를 한 번에 저장한다. 중간에 실패하면 아무것도 바꾸지 않는다.
    func save(sessions: [WorkSession], sources: [String: SourceState], notesByRoot: [String: [MemoryNote]]) throws {
        let now = Date()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try db.transaction {
            for s in sessions {
                try db.run("""
                    INSERT INTO sessions (key, tool, session_id, title, cwd, project_path, git_branch, start, end, active_seconds,
                        cost_usd, lines_added, lines_removed, subagents, source_path, has_transcript, source_missing,
                        tool_uses, models, files, skills, first_saved, updated)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(key) DO UPDATE SET
                        title = excluded.title, cwd = excluded.cwd, project_path = excluded.project_path,
                        git_branch = excluded.git_branch, start = excluded.start, end = excluded.end,
                        active_seconds = excluded.active_seconds, cost_usd = excluded.cost_usd,
                        lines_added = excluded.lines_added, lines_removed = excluded.lines_removed,
                        subagents = excluded.subagents, source_path = excluded.source_path,
                        has_transcript = excluded.has_transcript, source_missing = excluded.source_missing,
                        tool_uses = excluded.tool_uses, models = excluded.models, files = excluded.files,
                        skills = excluded.skills, updated = excluded.updated
                    """, [
                        s.id, s.tool.rawValue, s.sessionId, s.title, s.cwd, s.projectPath, s.gitBranch, s.start, s.end,
                        s.activeSeconds, s.costUSD, s.linesAdded, s.linesRemoved, s.subagents, s.sourcePath,
                        s.hasTranscript, s.sourceMissing, Self.encode(s.toolUses), Self.encode(s.models), Self.encode(s.files),
                        Self.encode(s.skillsUsed), now, now,
                    ])
                try db.run("DELETE FROM prompts WHERE session_key = ?", [s.id])
                for (i, p) in s.prompts.enumerated() {
                    try db.run("""
                        INSERT INTO prompts (session_key, idx, date, text, reply, is_command, is_automated, files, lines_added, lines_removed)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """, [s.id, i, p.date, p.text, p.reply, p.isCommand, p.isAutomated, Self.encode(p.files), p.linesAdded, p.linesRemoved])
                }
            }
            for (path, state) in sources {
                let blob = try encoder.encode(state.accumulator)
                try db.run("INSERT OR REPLACE INTO sources (path, size, offset, state, updated) VALUES (?, ?, ?, ?, ?)",
                           [path, state.size, state.offset, blob, now])
            }
            // 원본 메모가 지워져도 보관본은 남기고 표시만 한다.
            try db.run("UPDATE notes SET missing = 1")
            for (root, notes) in notesByRoot {
                for n in notes {
                    try db.run("""
                        INSERT OR REPLACE INTO notes (path, root, name, summary, kind, body, modified, missing)
                        VALUES (?, ?, ?, ?, ?, ?, ?, 0)
                        """, [n.path, root, n.name, n.summary, n.kind, n.body, n.modified])
                }
            }
        }
    }

    /// 저장 뒤 정리: 쓰기 대기 파일 내용을 본 파일로 옮겨 비우고, 빈 공간이 많으면 파일을 줄인다.
    func compact() {
        var pages = 0, free = 0
        try? db.query("PRAGMA page_count") { pages = $0.int(0) }
        try? db.query("PRAGMA freelist_count") { free = $0.int(0) }
        if pages > 0, Double(free) / Double(pages) > 0.2 { try? db.exec("VACUUM") }
        try? db.exec("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    /// 원본을 어디까지 읽었는지만 지운다. 다음에 원본을 처음부터 다시 읽지만, 보관된 세션은 남는다.
    public func eraseReadPositions() throws {
        try db.run("DELETE FROM sources")
    }

    public struct Stats: Sendable {
        public var sessions: Int
        public var prompts: Int
        public var preserved: Int
        public var bytes: Int
    }

    public func stats() -> Stats {
        var sessions = 0, prompts = 0, preserved = 0
        try? db.query("SELECT COUNT(*), SUM(source_missing) FROM sessions") { row in
            sessions = row.int(0)
            preserved = row.int(1)
        }
        try? db.query("SELECT COUNT(*) FROM prompts") { prompts = $0.int(0) }
        let fm = FileManager.default
        let bytes = [url.path, url.path + "-wal"].compactMap { (try? fm.attributesOfItem(atPath: $0))?[.size] as? Int }.reduce(0, +)
        return Stats(sessions: sessions, prompts: prompts, preserved: preserved, bytes: bytes)
    }

    // MARK: - 도우미

    private static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ text: String?) -> T? {
        guard let text, let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

extension WorkSession {
    /// 보관본과 새로 읽은 것을 합친다. 새것을 기본으로 하되, 보관본에만 있는 요청은 버리지 않는다.
    /// (원본이 줄어들거나 다른 도구가 오래된 항목을 지워도 기록이 사라지지 않게.)
    func merged(withArchived old: WorkSession) -> WorkSession {
        var result = self
        // 같은 요청인지는 보낸 시각(밀리초)으로 본다. 글 정리 규칙이 바뀌어도 같은 요청이 두 번 들어가지 않게.
        func key(_ p: PromptEntry) -> Int { Int((p.date.timeIntervalSince1970 * 1000).rounded()) }
        let fresh = Set(prompts.map(key))
        let lost = old.prompts.filter { !fresh.contains(key($0)) }
        if !lost.isEmpty {
            result.prompts = (prompts + lost).sorted { $0.date < $1.date }
            result.start = min(start, old.start)
            result.end = max(end, old.end)
        }
        // 답변이 있던 보관본을, 답변이 없는 기록(프롬프트만 남은 기록)으로 덮지 않는다.
        if old.hasTranscript && !hasTranscript { return old }
        return result
    }
}
