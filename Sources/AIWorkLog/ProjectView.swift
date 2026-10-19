import SwiftUI
import WorkLogCore

struct ProjectView: View {
    @Environment(AppModel.self) private var model
    var project: ProjectSummary

    private enum Tab: String, Hashable { case worklog, sessions, setup, notes }

    /// 화면 확인용: `--tab worklog|sessions|setup|notes` 로 시작 탭을 고른다.
    private static var launchTab: Tab {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--tab"), i + 1 < args.count else { return .worklog }
        return Tab(rawValue: args[i + 1]) ?? .worklog
    }

    @State private var tab: Tab = ProjectView.launchTab
    /// 막대를 눌러 고른 날. 그날 한 일만 본다.
    @State private var pickedDay: Date?
    /// 무한 스크롤: 지금까지 그린 날 수, 세션 수.
    @State private var dayLimit = ProjectView.dayPage
    @State private var sessionLimit = ProjectView.sessionPage

    static let dayPage = 7
    static let sessionPage = 20

    private var query: String { model.search.trimmingCharacters(in: .whitespaces) }

    /// 기간·고른 날·검색어로 거른 날짜별 작업 (최근 날 먼저).
    private var workDays: [DayGroup] {
        var days = WorkLogAnalytics.days(WorkLogAnalytics.clip(project.sessions, to: model.period.interval()))
        if let pickedDay { days = days.filter { Calendar.current.isDate($0.day, inSameDayAs: pickedDay) } }
        guard !query.isEmpty else { return days }
        return days.compactMap { day in
            var day = day
            day.entries = day.entries.compactMap { entry in
                var entry = entry
                entry.prompts = entry.prompts.filter { $0.text.contains(search: query) || ($0.reply?.contains(search: query) ?? false) }
                return entry.prompts.isEmpty ? nil : entry
            }
            return day.entries.isEmpty ? nil : day
        }
    }

    var body: some View {
        let inPeriod = WorkLogAnalytics.clip(project.sessions, to: model.period.interval())
        ScrollViewReader { proxy in
        ScrollView {
            // 목록이 이 스택에 바로 들어가야 맨 아래에 닿았을 때를 알 수 있어서 게으른 스택을 쓴다.
            LazyVStack(alignment: .leading, spacing: 12) {
                header
                TileRows(tiles: [
                    StatTile(label: L("작업 시간"), value: Fmt.duration(project.activeSeconds), caption: L("전체 기간"), symbol: "clock"),
                    StatTile(label: L("세션"), value: Fmt.number(project.sessions.count), caption: toolsCaption, symbol: "rectangle.stack"),
                    StatTile(label: L("요청"), value: Fmt.number(project.promptCount), caption: L("전체 기간"), symbol: "text.bubble"),
                    StatTile(label: L("처음 작업"), value: project.sessions.isEmpty ? "–" : Fmt.day(project.firstActive), caption: nil, symbol: "flag"),
                    StatTile(label: L("마지막 작업"), value: project.sessions.isEmpty ? "–" : Fmt.relativeDay(project.lastActive),
                             caption: project.sessions.isEmpty ? nil : Fmt.dateTime(project.lastActive), symbol: "clock.arrow.circlepath"),
                ])

                if !inPeriod.isEmpty {
                    Card(title: L("%@ 요청", model.period.longLabel), subtitle: L("막대를 누르면 그날 한 일만 봐요")) {
                        ActivityChart(sessions: inPeriod, period: model.period, onPick: pick, picked: pickedDay)
                            .frame(height: 160)
                    }
                }

                Picker(L("보기"), selection: $tab) {
                    Text(L("날짜별로 한 일")).tag(Tab.worklog)
                    Text(L("세션 %@", String(project.sessions.count))).tag(Tab.sessions)
                    Text(L("AI 규칙·스킬")).tag(Tab.setup)
                    Text(L("AI 메모 %@", String(project.notes.count))).tag(Tab.notes)
                }
                .pickerStyle(.segmented)
                .id("tabs")
                .labelsHidden()
                .fixedSize()
                .padding(.top, 6)

                switch tab {
                case .worklog: worklog
                case .sessions: sessions
                case .setup: setup
                case .notes: notes
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        // 시연 영상(--tour): 탭 줄까지 내려 날짜별 요약이 화면에 다 보이게.
        .onChange(of: model.tourScrollToTabs) {
            withAnimation(.easeInOut(duration: 0.6)) { proxy.scrollTo("tabs", anchor: .top) }
        }
        }
        .onChange(of: model.period) { pickedDay = nil; dayLimit = Self.dayPage }
        .onChange(of: model.search) { dayLimit = Self.dayPage }
        .onChange(of: pickedDay) { dayLimit = Self.dayPage }
    }

    private func pick(_ day: Date) {
        pickedDay = pickedDay.map { Calendar.current.isDate($0, inSameDayAs: day) } == true ? nil : day
        tab = .worklog
    }

    // MARK: 날짜별로 한 일

    @ViewBuilder
    private var worklog: some View {
        let days = workDays
        // Group 의 자식은 바깥 LazyVStack 에 하나씩 풀려 들어가서 날마다 따로 늦게 그려진다.
        Group {
            worklogSummary(days)
            if !days.isEmpty { NoSummaryEngineNote() }
            if days.isEmpty {
                emptyWorklog
            }
            ForEach(days.prefix(dayLimit)) { day in
                DayWorkCard(day: day, projectName: project.name, projectPath: project.path, highlight: query)
            }
            if days.count > dayLimit {
                LoadMoreRow(remaining: days.count - dayLimit) { dayLimit += Self.dayPage }
                    .id(dayLimit)
            }
        }
    }

    /// "최근 30일 · 12일 동안 요청 84개 · 약 9시간" + 걸려 있는 조건
    private func worklogSummary(_ days: [DayGroup]) -> some View {
        let prompts = days.reduce(0) { $0 + $1.promptCount }
        let seconds = days.reduce(0) { $0 + $1.activeSeconds }
        let files = Set(days.flatMap { $0.entries.flatMap(\.files) }).count
        var parts = [L("%@일 동안 요청 %@개", String(days.count), String(prompts)), L("약 %@", Fmt.duration(seconds))]
        if files > 0 { parts.append(L("파일 %@개 고침", String(files))) }
        return HStack(spacing: 8) {
            Text(pickedDay.map { Fmt.fullDay($0) } ?? model.period.longLabel).font(.callout.weight(.semibold))
            if !days.isEmpty { Text(parts.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary) }
            Spacer()
            if !query.isEmpty { Chip(text: L("‘%@’ 검색", query), symbol: "magnifyingglass") }
            if pickedDay != nil {
                Button { pickedDay = nil } label: { Label(L("이날만 보기 끄기"), systemImage: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            SummaryEngineMenu()
        }
    }

    @ViewBuilder
    private var emptyWorklog: some View {
        if project.sessions.isEmpty {
            EmptyCard(title: L("남은 대화 기록이 없어요"),
                      message: L("대화 기록이 지워져 AI 메모만 남은 프로젝트예요."),
                      symbol: "calendar") {
                if !project.notes.isEmpty { Button(L("AI 메모 보기")) { tab = .notes } }
            }
        } else if !query.isEmpty {
            EmptyCard(title: L("‘%@’ 와 맞는 작업이 없어요", query),
                      message: L("%@ 동안 이 프로젝트에서 보낸 요청과 AI 답에서 찾지 못했어요.", model.period.longLabel),
                      symbol: "magnifyingglass") {
                HStack {
                    Button(L("검색어 지우기")) { model.search = "" }
                    if model.period != .all { Button(L("전체 기간에서 찾기")) { model.period = .all } }
                }
            }
        } else {
            EmptyCard(title: L("%@에는 한 일이 없어요", model.period.longLabel),
                      message: L("이 프로젝트에서 마지막으로 일한 날: %@", Fmt.fullDay(project.lastActive)),
                      symbol: "calendar") {
                if model.period != .all { Button(L("전체 기간 보기")) { model.period = .all } }
            }
        }
    }

    // MARK: 세션 · 설정 · 메모

    @ViewBuilder
    private var sessions: some View {
        if project.sessions.isEmpty {
            EmptyCard(title: L("남은 세션이 없어요"),
                      message: L("대화 기록이 지워져 AI 메모만 남은 프로젝트예요."),
                      symbol: "rectangle.stack") {
                if !project.notes.isEmpty { Button(L("AI 메모 보기")) { tab = .notes } }
            }
        }
        ForEach(project.sessions.prefix(sessionLimit)) { session in
            Button { model.open(session) } label: {
                SessionRow(session: session)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 2)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.cardBorder))
            }
            .buttonStyle(.plain)
        }
        if project.sessions.count > sessionLimit {
            LoadMoreRow(remaining: project.sessions.count - sessionLimit) { sessionLimit += Self.sessionPage }
                .id(sessionLimit)
        }
    }

    @ViewBuilder
    private var setup: some View {
        if WorkLogAnalytics.configScopes(for: project.path, configs: model.snapshot.configs).isEmpty && project.skillsUsed.isEmpty {
            EmptyCard(title: L("만들어 둔 규칙·스킬이 없어요"),
                      message: L("이 폴더나 상위 폴더에 CLAUDE.md, AGENTS.md, .claude/skills 같은 파일이 생기면 여기에 보여요."),
                      symbol: "wand.and.stars")
        } else {
            ProjectConfigCard(project: project)
        }
    }

    @ViewBuilder
    private var notes: some View {
        if project.notes.isEmpty {
            EmptyCard(title: L("AI 가 남긴 메모가 없어요"),
                      message: L("Claude Code 가 이 프로젝트에 대해 기억해 둘 것이 생기면 여기에 보여요."),
                      symbol: "note.text")
        } else {
            Card(title: L("AI 가 남긴 메모"), subtitle: L("Claude Code 가 이 프로젝트에 대해 기억해 둔 내용 (%@개)", String(project.notes.count))) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(project.notes.enumerated()), id: \.element.id) { index, note in
                        NoteRow(note: note)
                        if index < project.notes.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    private var toolsCaption: String {
        AITool.chartOrder.filter(project.tools.contains).map(\.displayName).joined(separator: " · ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill").font(.title2).foregroundStyle(Color.accentColor)
                Text(project.name).font(.system(size: 28, weight: .bold))
            }
            Text(Fmt.path(project.path))
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if project.path.hasPrefix("/") {
                HStack(spacing: 8) {
                    Button { model.reveal(project.path) } label: { Label(L("Finder 에서 열기"), systemImage: "folder") }
                    Button { model.openTerminal(at: project.path) } label: { Label(L("터미널 열기"), systemImage: "terminal") }
                    Button { model.copy(project.path, message: L("경로를 복사했어요")) } label: { Label(L("경로 복사"), systemImage: "doc.on.doc") }
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
    }
}

/// 하루 동안 이 프로젝트에서 한 일.
/// 요약에 쓸 AI 가 있으면 AI 가 쓴 요약을 먼저 보여 주고, 세션마다 요청 → 결과 → 고친 파일은 접어 둔다.
struct DayWorkCard: View {
    @Environment(AppModel.self) private var model
    var day: DayGroup
    var projectName: String
    var projectPath: String
    var highlight: String?

    /// 사용자가 펼치거나 접은 상태. 정하지 않았으면 요약이 있을 때 접어 둔다.
    @State private var showDetails: Bool?

    private var searching: Bool { !(highlight ?? "").isEmpty }
    private var key: String { model.summaryKey(project: projectPath, day: day.day) }

    var body: some View {
        let files = Set(day.entries.flatMap(\.files))
        let added = day.entries.reduce(0) { $0 + $1.linesAdded }
        let removed = day.entries.reduce(0) { $0 + $1.linesRemoved }
        let hasSummary = model.summaries[key] != nil
        // 요약을 끄지 않았으면 저장해 둔 요약은 AI 가 없어도 보여 준다. 새로 만들 수 있을 때만 빈 요약 자리를 둔다.
        let summarized = model.summaryChoice != .off
            && (hasSummary || (model.summaryEngine != nil && DaySummarizer.promptCount(for: day) > 0))
        // 검색 중에는 찾은 요청이 보여야 하고, 아직 요약이 없는 오늘은 요청 목록이 본문이다.
        let expanded = searching || (showDetails ?? (!hasSummary || model.tourExpand))
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Fmt.relativeDay(day.day) == Fmt.day(day.day) ? Fmt.day(day.day) : "\(Fmt.relativeDay(day.day)) · \(Fmt.day(day.day))")
                    .font(.headline)
                Text(L("요청 %@ · %@", String(day.promptCount), Fmt.duration(day.activeSeconds)) + (files.isEmpty ? "" : " · " + L("파일 %@개", String(files.count))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if added + removed > 0 { LineDelta(added: added, removed: removed, approximate: true) }
                Spacer()
                Button {
                    model.makeReport(day: day, scope: projectName, projectPath: projectPath)
                } label: {
                    Label(L("이날 보고서"), systemImage: "doc.text")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help(L("이날 이 프로젝트에서 한 일을 마크다운으로 정리해요"))
            }

            if summarized {
                DaySummaryBox(projectPath: projectPath, projectName: projectName, day: day.day)
                if !searching {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { showDetails = !expanded }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                            Text(expanded ? L("요청 %@개 접기", String(day.promptCount)) : L("요청 %@개 자세히 보기", String(day.promptCount)))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if expanded { details }
            } else {
                details
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.cardBorder))
        // 화면에 보일 때만 요약을 맡기고, 기록을 새로 읽거나 도구를 바꾸면 다시 확인한다.
        .task(id: "\(Fmt.isoDay(day.day))|\(model.snapshot.loadedAt.timeIntervalSince1970)|\(model.summaryEngine?.id ?? "off")") {
            model.requestSummary(project: projectPath, name: projectName, day: day.day)
            // 오늘 아직 일하는 중이면, 손 뗀 지 30분이 되는 때에 기록을 다시 읽는다. 그때도 조용하면 위에서 요약을 맡긴다.
            guard let wake = model.summaryInputs[key]?.wakeAt else { return }
            try? await Task.sleep(for: .seconds(max(1, wake.timeIntervalSinceNow + 5)))
            if !Task.isCancelled { model.refresh() }
        }
        .onDisappear { model.cancelQueuedSummary(project: projectPath, day: day.day) }
    }

    /// 세션마다 요청 → 결과 → 고친 파일 (최신이 위).
    @ViewBuilder
    private var details: some View {
        ForEach(day.entries.sorted { $0.lastDate > $1.lastDate }) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Button { model.open(entry.session) } label: {
                    HStack(spacing: 8) {
                        Circle().fill(entry.session.tool.color).frame(width: 7, height: 7)
                        Text(entry.session.title).font(.callout.weight(.semibold)).lineLimit(1)
                        Text(Fmt.timeRange(entry.firstDate, entry.lastDate)).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(L("세션 열기")).font(.caption).foregroundStyle(.tertiary)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(entry.session.tool.displayName)

                let items = Array(entry.userPrompts.reversed().enumerated())
                ForEach(items, id: \.offset) { _, prompt in
                    Button { model.open(entry.session) } label: {
                        WorkItemRow(prompt: prompt, projectPath: entry.session.projectPath, highlight: highlight)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// AI 가 쓴 그날 요약: 한 줄 + 핵심 결과 몇 줄. 요약하는 중·기다리는 중·실패·새 요청도 여기서 알린다.
struct DaySummaryBox: View {
    @Environment(AppModel.self) private var model
    var projectPath: String
    var projectName: String
    var day: Date

    var body: some View {
        let key = model.summaryKey(project: projectPath, day: day)
        let summary = model.summaries[key]
        let job = model.summaryJobs[key]
        let busy = job == .queued || job == .running
        let input = model.summaryInputs[key]
        // 요약한 뒤로 생긴 요청 수, 오늘 손 뗀 지 30분이 되는 시각.
        let newer = summary == nil ? 0 : (input?.newSince ?? 0)
        let wake = input?.wakeAt
        let failure: String? = if case .failed(let message) = job { message } else { nil }
        // 요약할 AI 가 없으면 저장해 둔 요약만 보여 주고, 다시 만드는 버튼은 숨긴다.
        let canSummarize = model.summaryEngine != nil

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                Text(L("AI 요약")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let summary, !busy {
                    Text("· \(summary.engine)").font(.caption).foregroundStyle(.tertiary)
                        .help(L("%@에 요청 %@개까지 요약했어요", Fmt.dateTime(summary.created), String(summary.promptCount)))
                }
                Spacer()
                if busy {
                    ProgressView().controlSize(.mini)
                    Text(job == .queued ? L("차례를 기다리는 중…") : newer > 0 ? L("새 요청을 더하는 중…") : L("요약하는 중…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !canSummarize {
                    Text(L("요약할 AI 없음"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .help(L("저장해 둔 요약이에요. 새로 만들거나 이어 쓰려면 Claude Code·Codex·LM Studio 중 하나가 있어야 해요"))
                } else {
                    Button {
                        model.requestSummary(project: projectPath, name: projectName, day: day, force: true)
                    } label: {
                        Label(failure != nil ? L("다시 시도") : summary == nil ? L("지금까지 요약") : newer > 0 ? L("이어서 요약") : L("다시 요약"),
                              systemImage: summary == nil ? "sparkles" : newer > 0 ? "text.badge.plus" : "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help(buttonHelp(summary: summary, newer: newer))
                }
            }

            if let summary {
                Text(summary.headline)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(summary.points.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").foregroundStyle(.secondary)
                            Text(point).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                    }
                }
                .font(.callout)
                if newer > 0 && !busy {
                    Text(newerNote(newer, wake: wake, canSummarize: canSummarize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if busy {
                // 요약이 올 자리
                VStack(alignment: .leading, spacing: 7) {
                    Capsule().fill(.quaternary).frame(width: 240, height: 12)
                    Capsule().fill(.quaternary).frame(maxWidth: 420).frame(height: 9)
                    Capsule().fill(.quaternary).frame(maxWidth: 340).frame(height: 9)
                }
                .padding(.vertical, 2)
            } else if let wake, failure == nil {
                Text(L("아직 일하는 중이라 손을 떼고 30분이 지나면(%@쯤) 요약해요. 바로 보려면 \"지금까지 요약\"을 눌러 주세요", Fmt.time(wake)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func newerNote(_ newer: Int, wake: Date?, canSummarize: Bool) -> String {
        let head = L("요약한 뒤로 요청이 %@개 더 생겼어요.", String(newer))
        if !canSummarize { return head + L(" 요약할 AI 가 없어서 이어 쓰지 못해요") }
        if let wake { return head + " " + L("손을 떼고 30분이 지나면(%@쯤) 이어서 요약해요", Fmt.time(wake)) }
        if Calendar.current.isDateInToday(day) { return head }
        return head + L(" \"이어서 요약\"을 누르면 새 요청만 더해 정리해요")
    }

    private func buttonHelp(summary: DaySummary?, newer: Int) -> String {
        let destination = model.summaryEngine?.destination ?? "AI"
        if summary == nil { return L("기다리지 않고 지금까지 보낸 요청으로 바로 요약해요 (%@)", destination) }
        if newer > 0 { return L("새 요청 %@개만 %@에 보내 지금 요약에 더해요", String(newer), destination) }
        return L("그날 요청과 결과를 %@에 보내 처음부터 다시 요약해요", destination)
    }
}

/// 요약할 AI 를 찾지 못했을 때 날짜 목록 위에 띄우는 안내. 저장해 둔 요약은 그대로 보인다.
struct NoSummaryEngineNote: View {
    @Environment(AppModel.self) private var model
    /// 아무 도구도 없을 때의 안내는 닫을 수 있다 (메뉴의 "요약할 AI 없음"은 그대로).
    @AppStorage("hideNoSummaryEngineNote") private var hidden = false

    var body: some View {
        if let engines = model.summaryEngines, model.summaryEngine == nil, model.summaryChoice != .off,
           !(engines.isEmpty && hidden) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(engines)).font(.callout.weight(.semibold))
                    Text(message(engines))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(L("다시 찾기")) { model.findSummaryEngines() }
                if engines.isEmpty {
                    Button { hidden = true } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .help(L("안내 닫기"))
                } else {
                    Button(L("자동으로 바꾸기")) { model.summaryChoice = .auto }
                }
            }
            .controlSize(.small)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func title(_ engines: [SummaryEngine]) -> String {
        guard let kind = model.summaryChoice.kind, !engines.isEmpty else { return L("요약해 줄 AI 를 찾지 못했어요") }
        return kind == .lmStudio ? L("LM Studio 서버가 꺼져 있어요") : L("고른 %@를 찾지 못했어요", kind.displayName)
    }

    private func message(_ engines: [SummaryEngine]) -> String {
        guard let kind = model.summaryChoice.kind, !engines.isEmpty else {
            return L("이 맥에 Claude Code 나 Codex 를 설치하거나 LM Studio 서버를 켜면, 날마다 한 일을 AI 가 몇 줄로 요약해 줘요. ")
                + L("그 전까지는 요청 목록을 그대로 보여 주고, 저장해 둔 요약은 그대로 보여요.")
        }
        let fix = kind == .lmStudio ? L("LM Studio 에서 서버를 켠 뒤") : L("%@를 설치한 뒤", kind.displayName)
        return L("%@ 다시 찾기를 누르거나, 자동으로 바꾸면 이 맥에 있는 %@로 요약해요.", fix, engines.map(\.displayName).joined(separator: "·"))
    }
}

/// 날짜별 요약에 쓸 AI 고르기. 이 맥에 없는 도구는 "없음"으로 보여 준다.
struct SummaryEngineMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Menu {
            Picker(L("요약에 쓸 AI"), selection: $model.summaryChoice) {
                Text(L("자동 (요즘 가장 많이 쓴 도구)")).tag(SummaryChoice.auto)
                ForEach(SummaryEngine.Kind.allCases) { kind in
                    Text(model.summaryEngineLabel(kind)).tag(SummaryChoice(kind))
                }
                Text(L("끄기")).tag(SummaryChoice.off)
            }
            .pickerStyle(.inline)
            Divider()
            Button(L("AI 도구 다시 찾기")) { model.findSummaryEngines() }
            SettingsLink { Text(L("요약 설정…")) }
        } label: {
            Label(title, systemImage: "sparkles")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.caption)
        .help(model.summaryEngine.map { L("날짜마다 그날 요청과 결과를 %@에 보내 요약해요. 요약은 보관함에 남아서 한 번만 만들어요", $0.destination) }
              ?? L("이 맥에 있는 Claude Code·Codex·LM Studio 로 날짜마다 한 일을 요약해요"))
    }

    private var title: String {
        guard let engines = model.summaryEngines else { return L("AI 찾는 중…") }
        if model.summaryChoice == .off { return L("AI 요약 꺼짐") }
        if let engine = model.summaryEngine { return L("AI 요약 · %@", engine.displayName) }
        return engines.isEmpty ? L("요약할 AI 없음") : L("%@ 없음", model.summaryChoice.kind?.displayName ?? "AI")
    }
}

/// 요청 한 줄 → AI 가 해낸 결과 한 줄 → 고친 파일.
struct WorkItemRow: View {
    var prompt: PromptEntry
    var projectPath: String
    var highlight: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Fmt.time(prompt.date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(RichText.plain(RichText.snippet(prompt.text.singleLine, around: highlight), highlight: highlight))
                    .lineLimit(1)
                if let reply = prompt.reply {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "arrow.turn.down.right").font(.caption2)
                        Text(RichText.plain(RichText.snippet(reply.outcomeLine, around: highlight), highlight: highlight))
                            .lineLimit(1)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                if !prompt.files.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                        Text(fileSummary).lineLimit(1)
                        LineDelta(added: prompt.linesAdded, removed: prompt.linesRemoved, approximate: true)
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var fileSummary: String {
        let names = prompt.files.prefix(3).map { ($0 as NSString).lastPathComponent }
        let more = prompt.files.count > 3 ? " " + L("외 %@개", String(prompt.files.count - 3)) : ""
        return names.joined(separator: ", ") + more
    }
}

struct NoteRow: View {
    var note: MemoryNote
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.summary.isEmpty ? note.name : note.summary)
                            .font(.callout.weight(.medium))
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            if let kind = note.kind { Chip(text: kindLabel(kind)) }
                            Text(L("%@ 고침", Fmt.relativeDay(note.modified))).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                MarkdownText(text: note.body)
                    .font(.callout)
                    .padding(.leading, 22)
                    .padding(.bottom, 6)
            }
        }
        .padding(.vertical, 8)
    }

    private func kindLabel(_ kind: String) -> String {
        switch kind {
        case "project": return L("프로젝트")
        case "feedback": return L("작업 방식")
        case "user": return L("사용자")
        case "reference": return L("참고")
        default: return kind
        }
    }
}
