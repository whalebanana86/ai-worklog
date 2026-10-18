import SwiftUI
import WorkLogCore

struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    var session: WorkSession

    private enum Tab: String, CaseIterable, Identifiable {
        case conversation, files, tools
        var id: String { rawValue }
    }

    @State private var tab: Tab = .conversation
    @State private var showCommands = false
    /// 위쪽 검색어·기간을 무시하고 대화 전체를 볼지.
    @State private var showAllTurns = false
    /// 무한 스크롤: 지금까지 그린 턴 수.
    @State private var visibleCount = SessionDetailView.pageSize

    static let pageSize = 25

    private typealias Turn = (offset: Int, element: PromptEntry)

    private var query: String { model.search.trimmingCharacters(in: .whitespaces) }

    /// 위쪽 검색어·기간이 걸려 있는지.
    private var filterActive: Bool { !query.isEmpty || model.period != .all }

    /// 보여 줄 턴: 명령 숨기기 → 검색어·기간 거르기 → 최신이 위로.
    private var allTurns: [Turn] {
        Array(session.prompts.enumerated().filter { showCommands || !$0.element.isCommand })
    }

    private var shownTurns: [Turn] {
        var turns = allTurns
        if filterActive && !showAllTurns {
            let interval = model.period.interval()
            turns = turns.filter { _, p in
                (interval?.contains(p.date) ?? true) && (p.text.contains(search: query) || (p.reply?.contains(search: query) ?? false))
            }
        }
        return turns.reversed()
    }

    var body: some View {
        ScrollView {
            // 요청이 수백 개인 세션도 있어서, 화면에 보이는 턴만 그리도록 게으른 스택을 쓴다.
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                stats
                Picker("보기", selection: $tab) {
                    Text("대화 흐름 \(session.userPrompts.count)").tag(Tab.conversation)
                    Text("고친 파일 \(session.files.count)").tag(Tab.files)
                    Text("도구 · 모델").tag(Tab.tools)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                switch tab {
                case .conversation: conversation
                case .files: files
                case .tools: toolsAndModels
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        // 거르는 조건이 바뀌면 처음 묶음부터 다시.
        .onChange(of: model.search) { visibleCount = Self.pageSize }
        .onChange(of: model.period) { visibleCount = Self.pageSize; showAllTurns = false }
        .onChange(of: showCommands) { visibleCount = Self.pageSize }
        .onChange(of: showAllTurns) { visibleCount = Self.pageSize }
    }

    // MARK: 머리말

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ToolBadge(tool: session.tool)
                if !session.hasTranscript {
                    Chip(text: "요청만 남음", symbol: "text.badge.minus")
                        .help("대화 원본은 Claude Code 정리 기간이 지나 지워지고, 입력한 요청 기록만 남아 있어요")
                }
                if session.isAutomated { Chip(text: "자동 실행", symbol: "gearshape") }
                if session.subagents > 0 { Chip(text: "서브에이전트 \(session.subagents)", symbol: "person.2") }
                if session.sourceMissing {
                    Chip(text: "보관본", symbol: "archivebox")
                        .help("원본 기록 파일은 지워졌지만, 이 앱 보관함에 저장해 둔 내용이에요")
                }
                ForEach(session.skillsUsed.sorted { $0.value > $1.value }.prefix(4), id: \.key) { name, count in
                    Chip(text: count > 1 ? "\(name) ×\(count)" : name, symbol: "wand.and.stars")
                        .help("이 세션에서 쓴 스킬·명령")
                }
            }
            Text(session.title)
                .font(.system(size: 24, weight: .bold))
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Button { model.show(project: session.projectPath) } label: {
                    Label(session.projectName, systemImage: "folder")
                }
                .buttonStyle(.link)
                if let branch = session.gitBranch {
                    Label(branch, systemImage: "arrow.triangle.branch").foregroundStyle(.secondary)
                }
                Label(Fmt.timeRange(session.start, session.end), systemImage: "calendar").foregroundStyle(.secondary)
            }
            .font(.callout)
            if session.cwd != session.projectPath, !session.cwd.isEmpty {
                Text("\(Fmt.path(session.cwd)) 에서 실행").font(.caption).foregroundStyle(.secondary)
            }
            actions
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if let command = session.tool.resumeCommand(sessionId: session.sessionId, cwd: session.cwd), session.hasTranscript {
                Button {
                    model.copy(command, message: "터미널에 붙여 넣으면 이 대화를 이어서 할 수 있어요")
                } label: {
                    Label("이어서 작업하기", systemImage: "arrow.uturn.forward")
                }
                .help(command)
            }
            if !session.cwd.isEmpty {
                Button { model.openTerminal(at: session.projectPath.hasPrefix("/") ? session.projectPath : session.cwd) } label: {
                    Label("터미널 열기", systemImage: "terminal")
                }
            }
            if let source = session.sourcePath, !session.sourceMissing {
                Button { model.reveal(source) } label: { Label("원본 기록", systemImage: "doc.text.magnifyingglass") }
                    .help(Fmt.path(source))
            }
            Button { model.makeReport(session: session) } label: { Label("보고서", systemImage: "doc.text") }
        }
        .controlSize(.small)
    }

    private var stats: some View {
        var tiles = [
            StatTile(label: "작업 시간", value: Fmt.duration(session.activeSeconds), caption: Fmt.timeRange(session.start, session.end), symbol: "clock"),
            StatTile(label: "요청", value: Fmt.number(session.userPrompts.count), caption: nil, symbol: "text.bubble"),
            StatTile(label: "고친 파일", value: Fmt.number(session.files.count), caption: nil, symbol: "doc"),
            StatTile(label: "코드 변경", value: "+\(Fmt.compact(session.linesAdded ?? 0))",
                     caption: "−\(Fmt.compact(session.linesRemoved ?? 0))줄", symbol: "plus.forwardslash.minus"),
        ]
        if let cost = session.costUSD {
            tiles.append(StatTile(label: "비용", value: Fmt.cost(cost), caption: nil, symbol: "dollarsign.circle"))
        }
        tiles.append(StatTile(label: "토큰", value: Fmt.compact(session.totalTokens), caption: nil, symbol: "number"))
        return TileRows(tiles: tiles)
    }

    // MARK: 대화 흐름

    @ViewBuilder
    private var conversation: some View {
        let hasCommands = session.prompts.contains(where: \.isCommand)
        let turns = shownTurns
        let page = turns.prefix(visibleCount)
        // Group 의 자식은 바깥 LazyVStack 에 하나씩 풀려 들어가서 턴마다 따로 늦게 그려진다.
        Group {
            HStack(spacing: 12) {
                Label("최신 대화가 위", systemImage: "arrow.down").font(.caption).foregroundStyle(.secondary)
                if hasCommands {
                    Toggle("슬래시 명령도 보기", isOn: $showCommands).toggleStyle(.checkbox).font(.caption)
                }
            }
            if filterActive { filterBar(shown: turns.count) }
            if turns.isEmpty {
                Text(allTurns.isEmpty ? "남은 요청이 없어요" : "조건에 맞는 대화가 없어요").foregroundStyle(.secondary)
            }
            ForEach(Array(page.enumerated()), id: \.element.offset) { position, turn in
                let previous = position > 0 ? page[page.index(page.startIndex, offsetBy: position - 1)].element.date : nil
                TurnView(number: turn.offset + 1, prompt: turn.element, projectPath: session.projectPath,
                         showDay: previous.map { !Calendar.current.isDate(turn.element.date, inSameDayAs: $0) } ?? true,
                         isFirst: position == 0, highlight: showAllTurns ? nil : query)
            }
            if turns.count > visibleCount {
                LoadMoreRow(remaining: turns.count - visibleCount) { visibleCount += Self.pageSize }
                    .id(visibleCount)
            }
            if !session.hasTranscript {
                Label("대화 원본이 지워져서 AI 답변은 볼 수 없어요. 입력한 요청만 남아 있어요.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 위쪽 검색어·기간으로 대화를 거르고 있다는 안내.
    private func filterBar(shown: Int) -> some View {
        var conditions: [String] = []
        if !query.isEmpty { conditions.append("‘\(query)’ 검색") }
        if model.period != .all { conditions.append(model.period.longLabel) }
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill").foregroundStyle(Color.accentColor)
            if showAllTurns {
                Text("\(conditions.joined(separator: " · ")) 조건을 끄고 대화 전체 \(allTurns.count)개를 보는 중")
            } else {
                Text("\(conditions.joined(separator: " · ")) — 대화 \(allTurns.count)개 중 \(shown)개")
            }
            Spacer()
            Button(showAllTurns ? "조건 다시 적용" : "전체 대화 보기") { showAllTurns.toggle() }
                .controlSize(.small)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: 고친 파일

    private var files: some View {
        Card {
            if session.files.isEmpty {
                Text(session.hasTranscript ? "이 세션에서 고친 파일이 없어요" : "대화 원본이 없어서 고친 파일을 알 수 없어요")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(session.files.enumerated()), id: \.element.id) { index, file in
                        Button { model.reveal(file.path) } label: {
                            HStack {
                                Image(systemName: "doc.text").foregroundStyle(.secondary)
                                Text(Fmt.relativePath(file.path, to: session.projectPath))
                                    .font(.callout.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text("\(file.edits)번 수정").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Finder 에서 보기: \(Fmt.path(file.path))")
                        if index < session.files.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    // MARK: 도구 · 모델

    private var toolsAndModels: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "AI 가 쓴 도구") {
                if session.toolUses.isEmpty {
                    Text("도구 기록이 없어요").foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(session.toolUses.sorted { $0.value > $1.value }, id: \.key) { name, count in
                            Chip(text: "\(ToolLabel.korean(name)) \(Fmt.number(count))", symbol: ToolLabel.symbol(name))
                        }
                    }
                }
            }
            Card(title: "모델") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        Text("모델"); Text("입력"); Text("출력"); Text("캐시 읽기"); Text("캐시 쓰기"); Text("비용")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(session.models.sorted { $0.value.totalTokens > $1.value.totalTokens }, id: \.key) { name, u in
                        GridRow {
                            Text(name).font(.callout.monospaced())
                            if u.unsplitTokens > 0 {
                                Text("합계 \(Fmt.compact(u.unsplitTokens))").gridCellColumns(4)
                            } else {
                                Text(Fmt.compact(u.inputTokens))
                                Text(Fmt.compact(u.outputTokens))
                                Text(Fmt.compact(u.cacheReadTokens))
                                Text(Fmt.compact(u.cacheWriteTokens))
                            }
                            Text(u.costUSD.map(Fmt.cost) ?? "–")
                        }
                        .font(.callout.monospacedDigit())
                    }
                }
            }
        }
    }
}

/// 요청 하나와 그에 대한 AI 의 마지막 답.
struct TurnView: View {
    @Environment(AppModel.self) private var model
    var number: Int
    var prompt: PromptEntry
    var projectPath: String
    var showDay: Bool
    var isFirst: Bool
    var highlight: String?
    @State private var replyExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showDay {
                Text(Fmt.fullDay(prompt.date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, isFirst ? 0 : 8)
            }
            HStack(alignment: .top, spacing: 12) {
                Text(Fmt.time(prompt.date))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 8) {
                    request
                    if !prompt.files.isEmpty { files }
                    if let reply = prompt.reply { replyView(reply) }
                }
            }
        }
    }

    /// 내가 보낸 요청
    private var request: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: prompt.isCommand ? "command" : prompt.isAutomated ? "gearshape" : "person.fill")
                Text(prompt.isCommand ? "명령" : prompt.isAutomated ? "자동 요청" : "나")
                Text("#\(number)").foregroundStyle(.tertiary)
                Spacer()
                Button {
                    model.copy(prompt.text, message: "요청을 복사했어요")
                } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help("요청 복사")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Collapsible(isLong: prompt.text.looksLong, collapsedHeight: 140) {
                MarkdownText(text: prompt.text, highlight: highlight)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var files: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "pencil").foregroundStyle(.secondary).font(.caption)
            FlowLayout(spacing: 4) {
                ForEach(prompt.files.prefix(8), id: \.self) { path in
                    Button { model.reveal(path) } label: {
                        Chip(text: (path as NSString).lastPathComponent)
                    }
                    .buttonStyle(.plain)
                    .help(Fmt.relativePath(path, to: projectPath))
                }
                if prompt.files.count > 8 { Chip(text: "외 \(prompt.files.count - 8)개") }
                LineDelta(added: prompt.linesAdded, removed: prompt.linesRemoved, approximate: true)
            }
        }
        .padding(.leading, 4)
    }

    /// AI 의 마지막 답: 평소엔 한 줄, 누르면 전체.
    private func replyView(_ reply: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { replyExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "sparkle").foregroundStyle(.secondary)
                    if replyExpanded {
                        Text("AI 의 마지막 답").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    } else {
                        Text(RichText.plain(RichText.snippet(reply.plainLine.replacingOccurrences(of: "`", with: ""), around: highlight), highlight: highlight))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(replyExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(replyExpanded ? "접기" : "답변 전체 보기")

            if replyExpanded {
                MarkdownText(text: reply, highlight: highlight)
                HStack {
                    Spacer()
                    Button("답변 복사") { model.copy(reply, message: "답변을 복사했어요") }
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.cardBorder))
    }
}
