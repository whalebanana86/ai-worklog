import AppKit
import Foundation
import Observation
import WorkLogCore

enum Period: String, CaseIterable, Identifiable {
    case today, week, month, quarter, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return L("오늘")
        case .week: return L("7일")
        case .month: return L("30일")
        case .quarter: return L("90일")
        case .all: return L("전체")
        }
    }

    var longLabel: String {
        switch self {
        case .today: return L("오늘")
        case .week: return L("최근 7일")
        case .month: return L("최근 30일")
        case .quarter: return L("최근 90일")
        case .all: return L("전체 기간")
        }
    }

    var days: Int? {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .all: return nil
        }
    }

    func interval(now: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        guard let days else { return nil }
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let start = calendar.date(byAdding: .day, value: -days, to: end)!
        return DateInterval(start: start, end: end)
    }

    /// 견줄 바로 전 같은 길이 구간. 지금 구간은 아직 끝나지 않았으니, 끝도 "지금"에서 같은 날수만큼 뺀 때로 맞춘다
    /// (오늘 오전과 어제 하루 전체를 견주지 않게).
    func previousInterval(now: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        guard let days, let current = interval(now: now, calendar: calendar),
              let start = calendar.date(byAdding: .day, value: -days, to: current.start),
              let end = calendar.date(byAdding: .day, value: -days, to: now) else { return nil }
        return DateInterval(start: start, end: max(start, end))
    }

    /// "그 전 30일보다" 의 "그 전 30일".
    var previousLabel: String? {
        switch self {
        case .today: return L("어제 이맘때")
        case .week: return L("그 전 7일")
        case .month: return L("그 전 30일")
        case .quarter: return L("그 전 90일")
        case .all: return nil
        }
    }
}

enum Screen: Hashable {
    case dashboard
    case timeline
    case prompts
    case skills
    case project(String)
}

struct SessionLink: Hashable {
    var id: String
}

/// 날짜별 요약에 쓸 AI. "자동"은 이 맥에 있는 도구 중 요즘 가장 많이 쓴 것.
enum SummaryChoice: String, CaseIterable, Identifiable {
    case auto, claudeCode, codex, lmStudio, off

    var id: String { rawValue }

    var kind: SummaryEngine.Kind? {
        switch self {
        case .claudeCode: return .claudeCode
        case .codex: return .codex
        case .lmStudio: return .lmStudio
        case .auto, .off: return nil
        }
    }

    init(_ kind: SummaryEngine.Kind) {
        switch kind {
        case .claudeCode: self = .claudeCode
        case .codex: self = .codex
        case .lmStudio: self = .lmStudio
        }
    }
}

/// 그날 기록의 지금 상태 (화면 안내용).
struct SummaryInput: Equatable {
    /// 그날 사람이 보낸 요청 수.
    var promptCount: Int
    /// 저장된 요약 뒤로 생긴 요청 수.
    var newSince: Int
    /// 오늘 아직 일하는 중이면, 손 뗀 지 30분이 되어 요약할 시각.
    var wakeAt: Date?
}

/// 요약 하나가 어디까지 왔는지.
enum SummaryJob: Equatable {
    case queued, running
    case failed(String)
}

struct ReportDraft: Identifiable {
    let id = UUID()
    var title: String
    var markdown: String
    var fileName: String
}

@MainActor
@Observable
final class AppModel {
    private(set) var snapshot = WorkLogSnapshot.empty
    private(set) var isLoading = false
    private(set) var progress: Double?
    private(set) var hasLoaded = false

    var period: Period = .month { didSet { recompute() } }
    var tools: Set<AITool> = Set(AITool.allCases) { didSet { recompute() } }
    var includeAutomated = false { didSet { recompute() } }
    var search = "" { didSet { recompute() } }

    /// 화면 언어. 바꾸면 바로 모든 화면 글자가 바뀐다 (ContentView 가 `.id(language)` 로 새로 그린다).
    var language: AppLanguage = Loc.language {
        didSet {
            Loc.language = language
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.defaultsKey)
            // 편집·윈도우 같은 macOS 기본 메뉴는 다음에 앱을 열 때 이 언어로 나온다.
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
            recompute()
        }
    }

    /// 화면 모드. 고르면 바로 앱 전체에 쓰고 기억한다.
    var appearance: AppAppearance = AppAppearance.saved {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: AppAppearance.defaultsKey)
            appearance.apply()
        }
    }

    // 시연 영상(--tour)에서 화면을 움직이는 데 쓴다.
    var tourExpand = false
    var tourScrollToTabs = 0

    /// 오른쪽 정보 패널(프로젝트·세션의 자세한 숫자). 연 상태를 기억한다.
    var showInspector = UserDefaults.standard.object(forKey: "showInspector") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showInspector, forKey: "showInspector") }
    }

    var screen: Screen? = .dashboard
    var path: [SessionLink] = []
    var report: ReportDraft?
    var toast: String?

    // 화면이 다시 그려질 때마다 계산하지 않도록, 조건이 바뀔 때만 한 번 계산해 둔다.
    private(set) var filtered: [WorkSession] = []
    private(set) var scoped: [WorkSession] = []
    private(set) var days: [DayGroup] = []
    private(set) var projects: [ProjectSummary] = []
    private(set) var totals = WorkTotals(days: [], original: { _ in nil })
    /// 바로 전 같은 기간의 합계 (견주기용). 전체 기간이면 nil.
    private(set) var previousTotals: WorkTotals?
    private var byId: [String: WorkSession] = [:]

    // AI 날짜별 요약
    /// 이 맥에서 찾은 요약용 AI. 찾기 전에는 nil.
    private(set) var summaryEngines: [SummaryEngine]?
    var summaryChoice: SummaryChoice = SummaryChoice(rawValue: UserDefaults.standard.string(forKey: "summaryChoice") ?? "") ?? .auto {
        didSet {
            UserDefaults.standard.set(summaryChoice.rawValue, forKey: "summaryChoice")
            // 도구를 바꾸면 기다리던 것과 실패한 것은 새 도구로 다시 시도한다.
            pendingSummaries.removeAll()
            summaryJobs = summaryJobs.filter { $0.value == .running }
        }
    }
    /// 열쇠는 `DaySummary.key` (프로젝트 경로|yyyy-MM-dd).
    private(set) var summaries: [String: DaySummary] = [:]
    private(set) var summaryJobs: [String: SummaryJob] = [:]
    private(set) var summaryInputs: [String: SummaryInput] = [:]

    /// 지난 날짜를 한꺼번에 요약하는 중이면 (모두, 끝낸 수). 설정의 "지금 모두 만들기".
    private(set) var backlogProgress: (total: Int, done: Int)?

    /// `--demo`: 지어낸 기록으로 띄운다 (README 스크린샷용). 실제 기록·보관함을 읽지 않고 AI 도 부르지 않는다.
    let isDemo = ProcessInfo.processInfo.arguments.contains("--demo")
    /// `--no-ai`: 이 맥에 요약할 AI 가 하나도 없는 척한다 (화면 확인용).
    private let pretendNoAI = ProcessInfo.processInfo.arguments.contains("--no-ai")

    @ObservationIgnored private let loader = WorkLogLoader()
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSummaries: [PendingSummary] = []
    @ObservationIgnored private var runningSummaries = 0
    @ObservationIgnored private var enginesCheckedAt: Date?

    private struct PendingSummary {
        var key: String
        var project: String
        var day: String
        /// 처음부터 요약할 재료, 또는 이어 쓸 때는 그 뒤 기록만.
        var material: String
        /// 이어 쓸 지난 요약.
        var previous: DaySummary?
        var digest: String
        var promptCount: Int
        var coveredUntil: Date?
        /// 화면과 상관없이 맡긴 것(최근 지난 날 마감). 날짜 카드가 사라져도 빼지 않는다.
        var background: Bool
    }

    func refresh(rereadSources: Bool = false) {
        guard !isLoading else { return }
        if isDemo {
            // 기록과 요약을 같은 시각으로 만들어야 "요약한 뒤로 생긴 요청" 수가 맞는다.
            let now = Date()
            summaryEngines = pretendNoAI ? [] : [DemoData.engine]
            summaries = DemoData.summaries(now: now)
            apply(DemoData.snapshot(now: now))
            return
        }
        isLoading = true
        let loader = loader
        let model = self
        let firstTime = !hasLoaded
        if firstTime { findSummaryEngines() }
        Task {
            // 1) 보관함에 쌓인 기록부터 바로 보여 준다.
            if firstTime, let archived = await Task.detached(priority: .userInitiated, operation: { loader.loadArchived() }).value {
                await reloadSummaries()
                apply(archived)
            }
            // 2) 원본을 확인해 늘어난 부분만 읽어 보관함을 갱신한다.
            let snapshot = await Task.detached(priority: .userInitiated) { () -> WorkLogSnapshot in
                if rereadSources { loader.rereadSources() }
                return loader.load { done, total in
                    let value = Double(done) / Double(max(total, 1))
                    Task { @MainActor in model.progress = value }
                }
            }.value
            // 터미널(설치 때 미리 요약하기 등)에서 새로 저장한 요약도 불러온다.
            if !firstTime { await reloadSummaries() }
            apply(snapshot)
            self.isLoading = false
            self.progress = nil
            queueRecentBacklog()
        }
    }

    private func apply(_ snapshot: WorkLogSnapshot) {
        self.snapshot = snapshot
        byId = Dictionary(snapshot.sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        hasLoaded = true
        recompute()
    }

    var storeURL: URL? { loader.store?.url }

    /// 앱으로 돌아왔을 때: 마지막으로 읽은 지 1분이 넘었으면 기록을 다시 읽고,
    /// 그사이 Claude Code·Codex 를 깔았거나 LM Studio 서버를 켰을 수 있으니 AI 도구도 다시 찾는다.
    func appBecameActive() {
        guard hasLoaded else { return }
        if Date().timeIntervalSince(snapshot.loadedAt) > 60 { refresh() }
        if let checked = enginesCheckedAt, Date().timeIntervalSince(checked) > 60 { findSummaryEngines() }
    }

    func session(_ id: String) -> WorkSession? { byId[id] }

    func project(_ path: String) -> ProjectSummary? { projects.first { $0.path == path } }

    func open(_ session: WorkSession) { path.append(SessionLink(id: session.id)) }


    func show(project path: String) {
        screen = .project(path)
        self.path = []
    }

    private func recompute() {
        let query = search.trimmingCharacters(in: .whitespaces)
        filtered = snapshot.sessions.filter { s in
            tools.contains(s.tool) && (includeAutomated || !s.isAutomated) && (query.isEmpty || Self.matches(s, query))
        }
        scoped = WorkLogAnalytics.clip(filtered, to: period.interval())
        days = WorkLogAnalytics.days(scoped)
        totals = WorkTotals(days: days, original: { [byId] in byId[$0] })
        previousTotals = period.previousInterval().map { previous in
            WorkTotals(days: WorkLogAnalytics.days(WorkLogAnalytics.clip(filtered, to: previous)), original: { [byId] in byId[$0] })
        }
        // AI 메모는 Claude Code 가 남긴 것이라, 거르기에서 Claude Code 를 뺐으면 "메모만 남은" 프로젝트도 뺀다.
        projects = WorkLogAnalytics.projects(filtered, notesByRoot: query.isEmpty && tools.contains(.claudeCode) ? snapshot.notesByRoot : [:])
    }

    private static func matches(_ s: WorkSession, _ q: String) -> Bool {
        func has(_ text: String) -> Bool { text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        if has(s.title) || has(s.projectPath) { return true }
        return s.prompts.contains { has($0.text) || ($0.reply.map(has) ?? false) }
    }

    // MARK: - 동작

    func flash(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { toast = nil }
        }
    }

    func copy(_ text: String, message: String = L("복사했어요")) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash(message)
    }

    func reveal(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) {
            // open() 은 그 폴더가 .app 같은 묶음이면 실행해 버린다. Finder 로 보여 주기만 한다.
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
            flash(L("파일이 없어서 폴더를 열었어요"))
        } else {
            flash(L("지금은 없는 경로예요"))
        }
    }

    func openTerminal(at path: String) {
        // 터미널 앱은 폴더가 아닌 파일을 받으면 그 파일을 셸 스크립트로 실행한다. 경로는 기록에서 온 값이라 폴더일 때만 연다.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            flash(L("지금은 없는 폴더예요")); return
        }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - AI 날짜별 요약

    /// 지금 요약에 쓸 AI. 끔이거나 고른 도구가 이 맥에 없으면 nil.
    var summaryEngine: SummaryEngine? {
        guard let engines = summaryEngines, summaryChoice != .off else { return nil }
        if let kind = summaryChoice.kind { return engines.first { $0.kind == kind } }
        // 자동: 최근 30일에 가장 많이 쓴 도구. 클라우드 도구가 없을 때만 LM Studio.
        let since = Date().addingTimeInterval(-30 * 86_400)
        let recent = snapshot.sessions.filter { $0.end > since }
        func uses(_ e: SummaryEngine) -> Int { recent.filter { $0.tool == e.kind.tool }.count }
        let cloud = engines.filter { $0.kind != .lmStudio }
        return cloud.max { uses($0) < uses($1) } ?? engines.first
    }

    /// 보관함에 저장된 요약을 불러온다. 아직 저장 중인 것을 덮지 않게 더 새로 만든 쪽을 남긴다.
    private func reloadSummaries() async {
        let loader = loader
        let stored = await Task.detached { (try? loader.store?.loadSummaries()) ?? [:] }.value
        summaries.merge(stored) { mine, disk in mine.created >= disk.created ? mine : disk }
    }

    /// 고르기 메뉴에 쓰는 이름. 이 맥에 없는 도구는 "없음"을 붙인다.
    func summaryEngineLabel(_ kind: SummaryEngine.Kind) -> String {
        if summaryEngines?.contains(where: { $0.kind == kind }) == true { return kind.displayName }
        return kind == .lmStudio ? L("LM Studio (서버 꺼짐)") : L("%@ (설치 안 됨)", kind.displayName)
    }

    func findSummaryEngines() {
        guard !isDemo else { return }
        enginesCheckedAt = Date()
        if pretendNoAI {
            summaryEngines = []
            return
        }
        Task {
            summaryEngines = await DaySummarizer.detectEngines()
            summaryJobs = summaryJobs.filter { $0.value == .running }
            queueRecentBacklog()
        }
    }

    /// 최근 일주일 동안 끝난 날 중 요약이 없거나 마감 전인 것을 화면과 상관없이 맡긴다 (보통 어제 것 몇 개).
    /// 그보다 오래된 날은 설치 때 만들었거나, 그날을 볼 때 만든다.
    private func queueRecentBacklog() {
        guard !isDemo, snapshot.isSynced, summaryEngine != nil,
              let since = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date())) else { return }
        for item in DaySummarizer.backlog(sessions: snapshot.sessions, existing: summaries, since: since) {
            requestSummary(project: item.project, name: WorkSession.displayName(forPath: item.project), day: item.day, background: true)
        }
    }

    func summaryKey(project: String, day: Date) -> String { DaySummary.key(project: project, day: Fmt.isoDay(day)) }

    /// 날짜 카드가 보일 때 부른다. 무엇을 할지는 `DaySummarizer.plan` 이 정한다:
    /// 지난 날은 한 번 요약하면(마감하면) 그대로 쓰고, 오늘은 손 뗀 지 30분이 지나면 그 뒤 요청만 더해 이어 쓴다.
    /// `force` 는 버튼: 새 요청이 있으면 이어 쓰기, 없으면 처음부터 다시.
    func requestSummary(project path: String, name: String, day: Date, force: Bool = false, background: Bool = false) {
        // 요약할 AI 가 없어도 "요약한 뒤로 요청이 N개 더" 안내는 해야 하니 그날 상태는 먼저 잰다.
        let engine = summaryEngine
        let key = summaryKey(project: path, day: day)
        guard let source = DaySummarizer.source(project: path, day: day, sessions: snapshot.sessions),
              let full = DaySummarizer.material(for: source, projectName: name) else {
            summaryInputs[key] = nil
            return
        }
        let existing = summaries[key]
        let plan = DaySummarizer.plan(for: source, existing: existing, force: force)
        let count = DaySummarizer.promptCount(for: source)
        var wake: Date?
        if case .wait(let until) = plan, engine != nil { wake = until }
        let input = SummaryInput(promptCount: count, newSince: existing.map { DaySummarizer.newSince($0, in: source) } ?? count, wakeAt: wake)
        if summaryInputs[key] != input { summaryInputs[key] = input }
        guard let engine else { return }

        switch summaryJobs[key] {
        case .queued, .running: return
        case .failed: if !force { return }  // 실패한 날은 "다시 시도"를 눌렀을 때만
        case nil: break
        }
        if isDemo { return }
        var material = full
        var previous: DaySummary?
        switch plan {
        case .keep, .wait: return
        case .full: break
        case .update(let after):
            guard let rest = DaySummarizer.material(for: source, projectName: name, after: after) else { return }
            material = rest
            previous = existing
        }
        summaryJobs[key] = .queued
        pendingSummaries.append(PendingSummary(key: key, project: path, day: Fmt.isoDay(day), material: material, previous: previous,
                                               digest: DaySummarizer.digest(full), promptCount: count,
                                               coveredUntil: DaySummarizer.askedPrompts(in: source).last?.date, background: background))
        runSummaries(with: engine)
    }

    /// 요약을 직접 고쳐 쓴다. 고친 요약은 새 요청이 생겨도 저절로 바꾸지 않는다.
    func editSummary(key: String, headline: String, points: [String]) {
        guard let current = summaries[key] else { return }
        let headline = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !headline.isEmpty else { return }
        store(current.editing(headline: headline, points: points.filter { !$0.isEmpty }))
        flash(L("요약을 고쳤어요"))
    }

    /// 바로 전 요약으로 되돌린다. 한 번 더 하면 다시 돌아온다.
    func revertSummary(key: String) {
        guard let reverted = summaries[key]?.revertedToPrevious() else { return }
        store(reverted)
        flash(L("전 요약으로 되돌렸어요"))
    }

    private func store(_ summary: DaySummary) {
        summaries[summary.key] = summary
        let store = loader.store
        Task.detached(priority: .utility) { try? store?.saveSummary(summary) }
    }

    /// 아직 요약이 없거나 마감할 지난 날짜 수 (설정 화면에 보여 줌).
    var pastBacklogCount: Int { DaySummarizer.backlog(sessions: snapshot.sessions, existing: summaries).count }

    /// 설정의 "지금 모두 만들기": 설치 때 하는 지난 날짜 요약을 앱 안에서 한다. 화면과 상관없이 끝까지 간다.
    func summarizeAllPast() {
        guard !isDemo, summaryEngine != nil, backlogProgress == nil else { return }
        let items = DaySummarizer.backlog(sessions: snapshot.sessions, existing: summaries)
        guard !items.isEmpty else { return }
        backlogProgress = (items.count, 0)
        for item in items {
            requestSummary(project: item.project, name: WorkSession.displayName(forPath: item.project), day: item.day, background: true)
        }
    }

    /// "멈추기": 아직 시작하지 않은 것만 뺀다. 이미 만든 요약은 남는다.
    func stopSummarizingAll() {
        let dropped = pendingSummaries.filter(\.background).map(\.key)
        pendingSummaries.removeAll(where: \.background)
        for key in dropped { summaryJobs[key] = nil }
        backlogProgress = nil
    }

    /// 화면에서 사라진 날짜는 아직 시작하지 않았으면 빼서, 보이는 날짜부터 요약한다.
    func cancelQueuedSummary(project path: String, day: Date) {
        let key = summaryKey(project: path, day: day)
        guard summaryJobs[key] == .queued, pendingSummaries.contains(where: { $0.key == key && !$0.background }) else { return }
        pendingSummaries.removeAll { $0.key == key }
        summaryJobs[key] = nil
    }

    private func runSummaries(with engine: SummaryEngine) {
        // 클라우드 도구는 둘씩, 내 맥에서 도는 LM Studio 는 하나씩.
        let limit = engine.kind == .lmStudio ? 1 : 2
        while runningSummaries < limit, !pendingSummaries.isEmpty {
            let job = pendingSummaries.removeFirst()
            runningSummaries += 1
            summaryJobs[job.key] = .running
            let store = loader.store
            Task {
                let outcome: Result<(headline: String, points: [String]), Error>
                do {
                    outcome = .success(try await DaySummarizer.summarize(job.material, with: engine, previous: job.previous))
                } catch {
                    outcome = .failure(error)
                }
                runningSummaries -= 1
                switch outcome {
                case .success(let result):
                    // 있던 요약은 되돌리기용으로 남긴다.
                    let summary = DaySummary(project: job.project, day: job.day, digest: job.digest, engine: engine.displayName,
                                             headline: result.headline, points: result.points, promptCount: job.promptCount,
                                             coveredUntil: job.coveredUntil).replacing(summaries[job.key])
                    summaries[job.key] = summary
                    summaryJobs[job.key] = nil
                    if var input = summaryInputs[job.key] {
                        input.newSince = max(0, input.promptCount - job.promptCount)
                        input.wakeAt = nil
                        summaryInputs[job.key] = input
                    }
                    Task.detached(priority: .utility) { try? store?.saveSummary(summary) }
                case .failure(let error):
                    summaryJobs[job.key] = .failed((error as? SummaryError)?.description ?? error.localizedDescription)
                }
                if job.background, let progress = backlogProgress {
                    let done = progress.done + 1
                    backlogProgress = done >= progress.total || !pendingSummaries.contains(where: \.background) && runningSummaries == 0
                        ? nil : (progress.total, done)
                }
                if let current = summaryEngine { runSummaries(with: current) }
            }
        }
    }

    // MARK: - 보고서

    /// 하루치 보고서. `scope` 를 주면 그 프로젝트만 다룬 보고서라고 제목에 붙인다.
    func makeReport(day: DayGroup, scope: String? = nil, projectPath: String? = nil) {
        let name = scope.map { "\($0) · " } ?? ""
        let summary = projectPath.flatMap { summaries[summaryKey(project: $0, day: day.day)] }
        // 한 식으로 이으면 오래된 컴파일러가 타입을 못 정해서 나눠 만든다.
        let reportTitle: String = L("AI 작업일지") + " · " + name + Fmt.fullDay(day.day)
        let scopePart: String = scope.map { "\($0)-" } ?? ""
        let fileName: String = L("AI작업일지") + "-" + scopePart + Fmt.isoDay(day.day) + ".md"
        report = ReportDraft(
            title: name + L("%@ 작업일지", Fmt.fullDay(day.day)),
            markdown: ReportBuilder.markdown(title: reportTitle, entries: day.entries, summary: summary),
            fileName: fileName
        )
    }

    func makePeriodReport() {
        let entries = days.flatMap(\.entries)
        let merged = Dictionary(grouping: entries, by: \.session.id).compactMap { _, parts -> DayEntry? in
            guard var first = parts.first else { return nil }
            first.prompts = parts.flatMap(\.prompts).sorted { $0.date < $1.date }
            return first
        }
        let range: String
        if let first = days.last?.day, let last = days.first?.day, first != last {
            range = "\(Fmt.day(first)) ~ \(Fmt.day(last))"
        } else {
            range = days.first.map { Fmt.fullDay($0.day) } ?? period.longLabel
        }
        report = ReportDraft(
            title: L("%@ 작업 보고서", period.longLabel),
            markdown: ReportBuilder.markdown(title: L("AI 작업 보고서") + " · " + range, entries: merged, promptsPerSession: 3),
            fileName: L("AI작업보고서") + "-\(period.rawValue)-\(Fmt.isoDay(Date())).md"
        )
    }

    func makeReport(session: WorkSession) {
        let entry = DayEntry(session: session, prompts: session.prompts)
        report = ReportDraft(
            title: session.title,
            markdown: ReportBuilder.markdown(title: session.title, entries: [entry], promptsPerSession: 20),
            fileName: L("AI작업") + "-\(session.projectName)-\(Fmt.isoDay(session.start)).md"
        )
    }
}
