import Foundation

/// 터미널용 명령. 개발용 `worklog-cli` 와 앱의 `AIWorkLog cli …` 가 같이 쓴다.
///   (인자 없음)          전체 요약
///   --day 2026-10-16     그날 보고서(마크다운)
///   --day … --ai [claude|codex|lmstudio]   그날 프로젝트마다 AI 요약 (보관함에 남겨 앱이 그대로 씀)
///   --summarize [--ai …] [--dry-run]   아직 요약이 없는 지난 날짜를 모두 AI 로 요약해 보관함에 남김 (설치 때 한 번)
///   --auto-sync on|off|status   앱을 안 열어도 6시간마다 보관함 갱신 (launchd, 앱 설정과 같은 것)
///   --session <id>       세션 하나 자세히
///   --no-store           보관함 없이 원본만 처음부터 읽기
///   --quiet              보관함만 갱신하고 한 줄로 알리기 (설치·자동 보관용)
public enum WorkLogCommand {
    /// 돌려주는 값은 종료 코드.
    public static func run(_ args: [String]) -> Int32 {
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }

        if let mode = value(after: "--auto-sync") {
            let sync = AutoSync()
            switch mode {
            case "on":
                do {
                    try sync.enable()
                    print("자동 보관을 켰어요: 6시간마다 보관함을 갱신해요 (끄기: --auto-sync off, 또는 앱 설정)")
                    return 0
                } catch {
                    print("⚠️ \(error)")
                    return 1
                }
            case "off":
                sync.disable()
                print("자동 보관을 껐어요.")
                return 0
            default:
                print(sync.registeredProgram.map { "자동 보관: 켜짐 (\($0.joined(separator: " ")))" } ?? "자동 보관: 꺼짐")
                return 0
            }
        }

        let loader = WorkLogLoader(storeURL: args.contains("--no-store") ? nil : WorkLogStore.defaultURL)
        let started = Date()
        let snapshot = loader.load()
        let elapsed = Date().timeIntervalSince(started)

        if args.contains("--summarize") {
            return summarizeBacklog(snapshot.sessions, choice: value(after: "--ai"), store: loader.store, dryRun: args.contains("--dry-run"))
        }

        if let day = value(after: "--day") {
            let groups = WorkLogAnalytics.days(snapshot.sessions)
            guard let group = groups.first(where: { Fmt.isoDay($0.day) == day }) else {
                print("\(day) 에는 기록이 없습니다.")
                return 1
            }
            if args.contains("--ai") {
                return summarize(group, sessions: snapshot.sessions, choice: value(after: "--ai"), store: loader.store)
            }
            print(ReportBuilder.markdown(title: "AI 작업일지 · \(Fmt.fullDay(group.day))", entries: group.entries))
            return 0
        }

        if let id = value(after: "--session") {
            guard let s = snapshot.sessions.first(where: { $0.sessionId.hasPrefix(id) }) else {
                print("세션을 찾지 못했습니다: \(id)")
                return 1
            }
            print("[\(s.tool.displayName)] \(s.title)")
            print("폴더 \(Fmt.path(s.cwd)) → 프로젝트 \(Fmt.path(s.projectPath))  브랜치 \(s.gitBranch ?? "-")")
            print("\(Fmt.dateTime(s.start)) ~ \(Fmt.dateTime(s.end))  작업 \(Fmt.duration(s.activeSeconds))  원본 \(s.hasTranscript ? "있음" : "없음")")
            print("요청 \(s.userPrompts.count)  파일 \(s.files.count)  +\(s.linesAdded ?? 0)/-\(s.linesRemoved ?? 0)  비용 \(s.costUSD.map(Fmt.cost) ?? "-")  토큰 \(Fmt.compact(s.totalTokens))  서브에이전트 \(s.subagents)")
            print("도구 " + s.toolUses.sorted { $0.value > $1.value }.prefix(8).map { "\($0.key)×\($0.value)" }.joined(separator: " "))
            print("모델 " + s.models.map { "\($0.key) \(Fmt.compact($0.value.totalTokens))" }.joined(separator: ", "))
            for p in s.prompts.prefix(12) {
                let flag = p.isCommand ? "⌘" : (p.isAutomated ? "⚙︎" : "•")
                print("\(flag) \(Fmt.time(p.date)) \(p.text.singleLine.prefix(90))")
                if let r = p.reply { print("    ↳ \(r.singleLine.prefix(90))") }
            }
            for f in s.files.prefix(8) { print("  ✎ \(Fmt.relativePath(f.path, to: s.projectPath)) ×\(f.edits)") }
            return 0
        }

        let byId = Dictionary(snapshot.sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // 설치 스크립트·자동 보관용: 보관함만 갱신하고 한 줄로 알린다.
        if args.contains("--quiet") {
            let st = snapshot.store
            print("보관함 갱신: 세션 \(st?.sessions ?? snapshot.sessions.count)개, 요청 \(st?.prompts ?? 0)개 (\(String(format: "%.1f", elapsed))초)")
            for w in snapshot.warnings { print("⚠️ \(w)") }
            return snapshot.warnings.isEmpty ? 0 : 1
        }

        let totals = WorkTotals(days: WorkLogAnalytics.days(snapshot.sessions), original: { byId[$0] })
        print(String(format: "읽은 시간 %.2f초", elapsed))
        print("세션 \(totals.sessions)  요청 \(totals.prompts)  활동일 \(totals.activeDays)  프로젝트 \(totals.projects)")
        print("작업 \(Fmt.duration(totals.activeSeconds))  코드 +\(totals.linesAdded)/-\(totals.linesRemoved)  비용 \(Fmt.cost(totals.costUSD))  토큰 \(Fmt.compact(totals.tokens))")
        for tool in AITool.allCases {
            let list = snapshot.sessions.filter { $0.tool == tool }
            let withTranscript = list.filter(\.hasTranscript).count
            print("  \(tool.displayName): 세션 \(list.count) (원본 있음 \(withTranscript))")
        }
        for w in snapshot.warnings { print("⚠️ \(w)") }
        if let st = snapshot.store {
            print("보관함 세션 \(st.sessions) · 요청 \(st.prompts) · 원본 지워진 보관본 \(st.preserved) · \(ByteCountFormatter.string(fromByteCount: Int64(st.bytes), countStyle: .file))")
        }

        print("\n프로젝트 (최근 순)")
        for p in WorkLogAnalytics.projects(snapshot.sessions, notesByRoot: snapshot.notesByRoot).prefix(25) {
            print(String(format: "  %-28@ 세션 %3d  요청 %4d  메모 %2d  %@", p.name as NSString, p.sessions.count, p.promptCount, p.notes.count,
                         Fmt.relativeDay(p.lastActive) as NSString))
        }

        print("\n최근 세션")
        for s in snapshot.sessions.prefix(15) {
            print("  \(Fmt.dateTime(s.end))  [\(s.tool.displayName)] \(s.projectName) · \(s.title.prefix(50))  요청 \(s.userPrompts.count)  \(s.sessionId.prefix(8))")
        }
        return 0
    }

    /// `--day … --ai [claude|codex|lmstudio]`: 그날 프로젝트마다 AI 요약을 받아 찍고 보관함에 남긴다 (앱이 그대로 쓴다).
    private static func summarize(_ group: DayGroup, sessions: [WorkSession], choice: String?, store: WorkLogStore?) -> Int32 {
        guard let engine = pickEngine(choice) else {
            print("요약에 쓸 AI 도구를 찾지 못했습니다.")
            return 1
        }
        print("요약: \(engine.displayName) → \(engine.destination)")

        let paths = Set(group.entries.map(\.session.projectPath)).sorted()
        var failed = false
        for path in paths {
            let name = WorkSession.displayName(forPath: path)
            guard let day = DaySummarizer.source(project: path, day: group.day, sessions: sessions),
                  let material = DaySummarizer.material(for: day, projectName: name) else { continue }
            let started = Date()
            do {
                let result = try blocking { try await DaySummarizer.summarize(material, with: engine) }
                let count = DaySummarizer.promptCount(for: day)
                print("\n## \(name)  (요청 \(count)개, \(String(format: "%.1f", Date().timeIntervalSince(started)))초)")
                print(result.headline)
                for point in result.points { print("- \(point)") }
                try? store?.saveSummary(DaySummary(project: path, day: Fmt.isoDay(group.day), digest: DaySummarizer.digest(material),
                                                   engine: engine.displayName, headline: result.headline, points: result.points,
                                                   promptCount: count, coveredUntil: DaySummarizer.askedPrompts(in: day).last?.date))
            } catch {
                failed = true
                print("\n## \(name)\n⚠️ \(error)")
            }
        }
        return failed ? 1 : 0
    }

    /// `--ai claude|codex|lmstudio` 로 고른 도구, 없으면 찾은 것 중 클라우드 도구 먼저.
    private static func pickEngine(_ choice: String?) -> SummaryEngine? {
        let engines = (try? blocking { await DaySummarizer.detectEngines() }) ?? []
        let wanted: SummaryEngine.Kind? = switch choice {
        case "claude": .claudeCode
        case "codex": .codex
        case "lmstudio": .lmStudio
        default: nil
        }
        if let wanted { return engines.first { $0.kind == wanted } }
        return engines.first { $0.kind != .lmStudio } ?? engines.first
    }

    private struct SummaryJob: Sendable {
        var project: String
        var day: String
        /// 처음부터 요약할 재료, 또는 이어 쓸 때는 그 뒤 기록만.
        var material: String
        /// 이어 쓸 지난 요약.
        var previous: DaySummary?
        var digest: String
        var promptCount: Int
        var coveredUntil: Date?
    }

    /// `--summarize`: 아직 요약이 없는 지난 날짜를 모두 요약해 하나씩 보관함에 남긴다.
    /// 설치 때 한 번 돌리면 앱은 저장된 요약을 불러 보여 주기만 한다. 중간에 멈춰도 다시 돌리면 남은 것만 한다.
    private static func summarizeBacklog(_ sessions: [WorkSession], choice: String?, store: WorkLogStore?, dryRun: Bool) -> Int32 {
        guard let store else {
            print("보관함 없이는 요약을 남길 수 없습니다.")
            return 1
        }
        let existing = (try? store.loadSummaries()) ?? [:]
        let jobs = DaySummarizer.backlog(sessions: sessions, existing: existing).compactMap { item -> SummaryJob? in
            let name = WorkSession.displayName(forPath: item.project)
            let key = DaySummary.key(project: item.project, day: Fmt.isoDay(item.day))
            guard let day = DaySummarizer.source(project: item.project, day: item.day, sessions: sessions),
                  let full = DaySummarizer.material(for: day, projectName: name) else { return nil }
            // 그날이 끝나기 전에 만든 요약은 남은 요청만 더해 마감한다.
            var material = full
            var previous: DaySummary?
            if case .update(let after) = item.plan, let old = existing[key],
               let rest = DaySummarizer.material(for: day, projectName: name, after: after) {
                material = rest
                previous = old
            }
            return SummaryJob(project: item.project, day: Fmt.isoDay(item.day), material: material, previous: previous,
                              digest: DaySummarizer.digest(full), promptCount: DaySummarizer.promptCount(for: day),
                              coveredUntil: DaySummarizer.askedPrompts(in: day).last?.date)
        }
        guard !jobs.isEmpty else {
            print("AI 요약: 새로 요약하거나 마감할 지난 날짜가 없어요 (저장된 요약 \(existing.count)개)")
            return 0
        }
        guard let engine = pickEngine(choice) else {
            print("AI 요약: 이 맥에서 요약에 쓸 AI 도구(Claude Code·Codex·LM Studio)를 찾지 못해 건너뛰어요.")
            return 0
        }
        // 클라우드 도구는 셋씩, 내 맥에서 도는 LM Studio 는 하나씩.
        let width = engine.kind == .lmStudio ? 1 : 3
        let chars = jobs.reduce(0) { $0 + $1.material.count }
        let closing = jobs.filter { $0.previous != nil }.count
        print("AI 요약: 지난 날짜 \(jobs.count)개\(closing > 0 ? "(그중 마감 \(closing)개)" : "")(재료 \(Fmt.compact(chars))자)를 \(engine.displayName)로 요약해요. 재료는 \(engine.destination)로 가요.")
        if dryRun { return 0 }

        let started = Date()
        let tty = isatty(STDOUT_FILENO) != 0
        let outcome: (done: Int, failed: Int, stopped: String?) = (try? blocking { () async -> (done: Int, failed: Int, stopped: String?) in
            await withTaskGroup(of: (SummaryJob, String?).self) { group in
                var next = 0, done = 0, failed = 0, streak = 0
                var stopped: String?
                func work(_ job: SummaryJob) async -> (SummaryJob, String?) {
                    do {
                        let result = try await DaySummarizer.summarize(job.material, with: engine, previous: job.previous)
                        try store.saveSummary(DaySummary(project: job.project, day: job.day, digest: job.digest,
                                                         engine: engine.displayName, headline: result.headline, points: result.points,
                                                         promptCount: job.promptCount, coveredUntil: job.coveredUntil))
                        return (job, nil)
                    } catch {
                        return (job, "\(error)")
                    }
                }
                while next < min(width, jobs.count) {
                    let job = jobs[next]
                    next += 1
                    group.addTask { await work(job) }
                }
                while let (job, error) = await group.next() {
                    if let error {
                        failed += 1
                        streak += 1
                        print("\(tty ? "\r" : "")⚠️ \(WorkSession.displayName(forPath: job.project)) \(job.day): \(error)")
                        // 로그인이 풀렸거나 사용량이 다 찼을 때 남은 것을 다 실패하며 기다리지 않게.
                        if streak >= 5 {
                            stopped = error
                            group.cancelAll()
                            break
                        }
                    } else {
                        done += 1
                        streak = 0
                    }
                    let finished = done + failed
                    if tty {
                        print("\r  \(finished)/\(jobs.count) 요약함", terminator: "")
                        fflush(stdout)
                    } else if finished % 25 == 0 {
                        print("  \(finished)/\(jobs.count) 요약함")
                    }
                    if next < jobs.count {
                        let job = jobs[next]
                        next += 1
                        group.addTask { await work(job) }
                    }
                }
                return (done, failed, stopped)
            }
        }) ?? (0, 0, nil)
        if tty { print("") }
        let took = Fmt.duration(Date().timeIntervalSince(started))
        if let stopped = outcome.stopped {
            print("AI 요약: 연달아 실패해서 멈췄어요 (\(stopped)). 저장한 \(outcome.done)개는 남고, 다시 돌리면 남은 것만 해요.")
        }
        print("AI 요약 끝: 새로 \(outcome.done)개 저장 · 실패 \(outcome.failed)개 (\(took))")
        return outcome.done == 0 && outcome.failed > 0 ? 1 : 0
    }

    /// 동기 명령 안에서 비동기 작업을 끝까지 기다린다.
    private static func blocking<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
        let box = ResultBox<T>()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do { box.result = .success(try await work()) } catch { box.result = .failure(error) }
            done.signal()
        }
        done.wait()
        return try box.result!.get()
    }
}

private final class ResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}
