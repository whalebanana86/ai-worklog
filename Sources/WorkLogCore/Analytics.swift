import Foundation

/// 하루치 작업에서 한 세션이 차지한 부분.
public struct DayEntry: Hashable, Sendable, Identifiable {
    public var session: WorkSession
    /// 그날 보낸 요청만.
    public var prompts: [PromptEntry]
    /// 그날 보낸 요청으로 AI 가 일한 구간.
    public var spans: [WorkSpan]
    /// 며칠에 걸친 세션은 날마다 한 줄씩 생기므로 날짜까지 붙여야 겹치지 않는다.
    public var id: String { "\(session.id)@\(Int(Calendar.current.startOfDay(for: firstDate).timeIntervalSince1970))" }

    public init(session: WorkSession, prompts: [PromptEntry], spans: [WorkSpan] = []) {
        self.session = session
        self.prompts = prompts
        self.spans = spans
    }

    public var userPrompts: [PromptEntry] { prompts.filter { !$0.isCommand } }
    /// 이날 작업 시간: 요청 시각과 AI 가 일한 구간을 이어 재고, 10분 넘게 빈 곳은 뺀다 (`ActiveClock.seconds`).
    public var activeSeconds: Double {
        if prompts.isEmpty && spans.isEmpty { return ActiveClock.seconds(points: [session.start, session.end], spans: []) }
        return ActiveClock.seconds(points: prompts.map(\.date), spans: spans)
    }
    /// 이날 요청들로 고친 파일.
    public var files: [String] {
        var seen = Set<String>()
        return prompts.flatMap(\.files).filter { seen.insert($0).inserted }
    }
    public var linesAdded: Int { prompts.reduce(0) { $0 + $1.linesAdded } }
    public var linesRemoved: Int { prompts.reduce(0) { $0 + $1.linesRemoved } }
    public var firstDate: Date { prompts.first?.date ?? session.start }
    public var lastDate: Date { prompts.last?.date ?? session.end }
}

public struct DayGroup: Hashable, Sendable, Identifiable {
    public var day: Date
    public var entries: [DayEntry]
    public var id: Date { day }

    public var promptCount: Int { entries.reduce(0) { $0 + $1.userPrompts.count } }
    /// 그날 작업 시간. 같은 때 돌린 세션은 세션마다 따로 잰 값을 더한다.
    public var activeSeconds: Double { entries.reduce(0) { $0 + $1.activeSeconds } }
}

extension WorkSession {
    /// AI 가 일한 구간마다, 그 일을 시킨 요청의 시각 (구간이 시작될 때 마지막으로 보낸 요청).
    /// 날짜·기간은 요청 시각으로 나누므로, 자정을 넘긴 작업도 요청한 날에 센다.
    func spansByRequest() -> [(span: WorkSpan, request: Date)] {
        let dates = prompts.map(\.date).sorted()
        guard !dates.isEmpty else { return spans.map { ($0, start) } }
        var i = 0
        return spans.sorted { $0.start < $1.start }.map { span in
            // 응답 시간은 요청 줄보다 몇 밀리초 앞에서 시작하기도 한다.
            let started = span.start.addingTimeInterval(5)
            while i + 1 < dates.count, dates[i + 1] <= started { i += 1 }
            return (span, dates[i])
        }
    }
}

public struct DailyCount: Hashable, Sendable, Identifiable {
    public var day: Date
    public var tool: AITool
    public var prompts: Int
    public var id: String { "\(day.timeIntervalSince1970)-\(tool.rawValue)" }
}

public struct ModelTotal: Hashable, Sendable, Identifiable {
    public var model: String
    public var tokens: Int
    public var outputTokens: Int
    public var costUSD: Double?
    public var sessions: Int
    public var id: String { model }
}

public enum WorkLogAnalytics {
    public static func projects(_ sessions: [WorkSession], notesByRoot: [String: [MemoryNote]]) -> [ProjectSummary] {
        let grouped = Dictionary(grouping: sessions, by: \.projectPath)
        var paths = Set(grouped.keys)
        // 메모만 있고 세션 기록은 지워진 프로젝트도 보여 준다.
        paths.formUnion(notesByRoot.keys)
        return paths.map { path in
            ProjectSummary(path: path,
                           sessions: (grouped[path] ?? []).sorted { $0.end > $1.end },
                           notes: notes(for: path, notesByRoot: notesByRoot))
        }
        .sorted { $0.lastActive > $1.lastActive }
    }

    /// 그 폴더의 메모 + 상위 폴더 메모 중 이 프로젝트 이름이 나오는 것.
    public static func notes(for path: String, notesByRoot: [String: [MemoryNote]]) -> [MemoryNote] {
        var result = notesByRoot[path] ?? []
        let name = (path as NSString).lastPathComponent.lowercased()
        guard name.count >= 3 else { return result }
        let variants = Set([name, name.replacingOccurrences(of: "_", with: "-"), name.replacingOccurrences(of: "-", with: "_")])
        for (root, notes) in notesByRoot where root != path && path.hasPrefix(root + "/") {
            result += notes.filter { note in
                let hay = ((note.path as NSString).lastPathComponent + " " + note.name + " " + note.summary + " " + note.body.prefix(300)).lowercased()
                return variants.contains { hay.contains($0) }
            }
        }
        return result
    }

    /// 요청을 보낸 날짜별로 묶는다. 며칠에 걸친 세션은 요청을 보낸 날마다 나온다.
    public static func days(_ sessions: [WorkSession], calendar: Calendar = .current) -> [DayGroup] {
        var buckets: [Date: [DayEntry]] = [:]
        for session in sessions {
            let byDay = Dictionary(grouping: session.prompts) { calendar.startOfDay(for: $0.date) }
            if byDay.isEmpty {
                buckets[calendar.startOfDay(for: session.start), default: []].append(DayEntry(session: session, prompts: [], spans: session.spans))
                continue
            }
            let spansByDay = Dictionary(grouping: session.spansByRequest()) { calendar.startOfDay(for: $0.request) }
            for (day, prompts) in byDay {
                buckets[day, default: []].append(DayEntry(session: session, prompts: prompts.sorted { $0.date < $1.date },
                                                          spans: spansByDay[day]?.map(\.span) ?? []))
            }
        }
        return buckets.map { day, entries in
            DayGroup(day: day, entries: entries.sorted { $0.firstDate > $1.firstDate })
        }
        .sorted { $0.day > $1.day }
    }

    public static func dailyCounts(_ sessions: [WorkSession], calendar: Calendar = .current) -> [DailyCount] {
        var counts: [Date: [AITool: Int]] = [:]
        for s in sessions {
            for p in s.prompts where !p.isCommand {
                counts[calendar.startOfDay(for: p.date), default: [:]][s.tool, default: 0] += 1
            }
        }
        return counts.flatMap { day, tools in
            tools.map { DailyCount(day: day, tool: $0.key, prompts: $0.value) }
        }
        .sorted { $0.day < $1.day }
    }

    /// [요일 0=일요일][시 0~23] 요청 수.
    public static func weekHourGrid(_ sessions: [WorkSession], calendar: Calendar = .current) -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        for s in sessions {
            for p in s.prompts where !p.isCommand {
                let c = calendar.dateComponents([.weekday, .hour], from: p.date)
                if let w = c.weekday, let h = c.hour { grid[w - 1][h] += 1 }
            }
        }
        return grid
    }

    public static func modelTotals(_ sessions: [WorkSession]) -> [ModelTotal] {
        var totals: [String: ModelTotal] = [:]
        for s in sessions {
            for (model, u) in s.models where u.totalTokens > 0 || (u.costUSD ?? 0) > 0 {
                var t = totals[model] ?? ModelTotal(model: model, tokens: 0, outputTokens: 0, costUSD: nil, sessions: 0)
                t.tokens += u.totalTokens
                t.outputTokens += u.outputTokens
                if let c = u.costUSD { t.costUSD = (t.costUSD ?? 0) + c }
                t.sessions += 1
                totals[model] = t
            }
        }
        return totals.values.sorted { $0.tokens > $1.tokens }
    }

    /// 기간 안에 요청이 있었던 세션만, 요청과 AI 가 일한 구간도 그 기간 요청의 것만 남긴다.
    public static func clip(_ sessions: [WorkSession], to interval: DateInterval?) -> [WorkSession] {
        guard let interval else { return sessions }
        return sessions.compactMap { s in
            if s.prompts.isEmpty { return interval.contains(s.start) ? s : nil }
            let inside = s.prompts.filter { interval.contains($0.date) }
            guard !inside.isEmpty else { return nil }
            if inside.count == s.prompts.count { return s }
            var copy = s
            copy.prompts = inside
            copy.spans = s.spansByRequest().filter { interval.contains($0.request) }.map(\.span)
            return copy
        }
    }
}

/// 기간 통계. 며칠에 걸친 세션은 그 기간에 보낸 요청만큼만 센다.
public struct WorkTotals: Sendable {
    public var sessions = 0
    public var prompts = 0
    public var activeSeconds = 0.0
    public var linesAdded = 0
    public var linesRemoved = 0
    public var files = 0
    /// 세션 비용을 그 기간 요청 비율만큼 나눈 값.
    public var costUSD = 0.0
    public var tokens = 0
    public var activeDays = 0
    public var projects = 0

    /// `original` 은 기간으로 자르기 전 세션 (비율 계산용).
    public init(days: [DayGroup], original: (String) -> WorkSession?) {
        var sessionIds = Set<String>()
        var files = Set<String>()
        var projects = Set<String>()
        var share: [String: (inPeriod: Int, session: WorkSession)] = [:]
        for day in days {
            activeSeconds += day.activeSeconds
            for e in day.entries {
                sessionIds.insert(e.session.id)
                projects.insert(e.session.projectPath)
                prompts += e.userPrompts.count
                linesAdded += e.linesAdded
                linesRemoved += e.linesRemoved
                files.formUnion(e.files)
                let full = original(e.session.id) ?? e.session
                share[e.session.id, default: (0, full)].inPeriod += e.prompts.count
            }
        }
        for (_, v) in share {
            let total = max(v.session.prompts.count, 1)
            let ratio = v.session.prompts.isEmpty ? 1 : min(1, Double(v.inPeriod) / Double(total))
            costUSD += (v.session.costUSD ?? 0) * ratio
            tokens += Int(Double(v.session.totalTokens) * ratio)
        }
        sessions = sessionIds.count
        self.files = files.count
        self.projects = projects.count
        activeDays = days.count
    }
}

/// 프로젝트 하나의 기간 합계 (프로젝트 화면 머리·정보 패널). 한눈에 보기 숫자와 같은 방법으로 센다.
public struct ProjectPeriodTotals: Sendable {
    public var totals: WorkTotals
    /// 기간 안에서 쓴 AI 도구.
    public var tools: Set<AITool>
    /// 기간 안 첫 요청과 마지막 요청.
    public var first: Date?
    public var last: Date?
}

extension ProjectSummary {
    /// `interval` 이 nil 이면 전체 기간.
    public func totals(in interval: DateInterval?) -> ProjectPeriodTotals {
        let clipped = WorkLogAnalytics.clip(sessions, to: interval)
        let byId = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let dates = clipped.flatMap(\.userPrompts).map(\.date)
        return ProjectPeriodTotals(totals: WorkTotals(days: WorkLogAnalytics.days(clipped), original: { byId[$0] }),
                                   tools: Set(clipped.filter { !$0.userPrompts.isEmpty }.map(\.tool)),
                                   first: dates.min(), last: dates.max())
    }
}

public struct ProjectTime: Hashable, Sendable, Identifiable {
    public var path: String
    public var seconds: Double
    public var prompts: Int
    public var id: String { path }
    public var name: String { WorkSession.displayName(forPath: path) }
}

extension WorkLogAnalytics {
    /// 기간 안 프로젝트별 작업 시간 (날짜별 작업 시간과 같은 방법), 많은 순.
    public static func projectTimes(_ days: [DayGroup]) -> [ProjectTime] {
        var map: [String: ProjectTime] = [:]
        for day in days {
            for e in day.entries {
                var t = map[e.session.projectPath] ?? ProjectTime(path: e.session.projectPath, seconds: 0, prompts: 0)
                t.seconds += e.activeSeconds
                t.prompts += e.userPrompts.count
                map[e.session.projectPath] = t
            }
        }
        return map.values.sorted { $0.seconds > $1.seconds }
    }

    /// 많이 쓴 도구(Bash, Edit, 웹 검색 …) 합계.
    public static func toolTotals(_ sessions: [WorkSession]) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for s in sessions { for (k, v) in s.toolUses { counts[k, default: 0] += v } }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}

extension WorkLogAnalytics {
    /// 한 프로젝트에 적용되는 AI 설정: 그 폴더 것 + 상위 폴더 것 (가까운 순).
    public static func configScopes(for path: String, configs: [String: [AIConfigItem]]) -> [AIConfigScope] {
        var scopes: [AIConfigScope] = []
        if let own = configs[path] { scopes.append(AIConfigScope(title: L("이 프로젝트"), path: path, items: own)) }
        var dir = (path as NSString).deletingLastPathComponent
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        while dir.hasPrefix(home + "/") {
            if let items = configs[dir] {
                scopes.append(AIConfigScope(title: L("상위 폴더 · %@", (dir as NSString).lastPathComponent), path: dir, items: items))
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return scopes
    }

    /// 스킬·명령 사용 횟수 합계와 쓴 프로젝트.
    public static func skillUsage(_ sessions: [WorkSession]) -> [(name: String, count: Int, projects: [String])] {
        var counts: [String: Int] = [:]
        var projects: [String: Set<String>] = [:]
        for s in sessions {
            for (k, v) in s.skillsUsed {
                counts[k, default: 0] += v
                projects[k, default: []].insert(s.projectName)
            }
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { ($0.key, $0.value, (projects[$0.key] ?? []).sorted()) }
    }
}
