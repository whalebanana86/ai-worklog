import SwiftUI
import WorkLogCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            DetailArea()
        }
        .searchable(text: $model.search, placement: .sidebar, prompt: "요청·답변·프로젝트 검색")
        .overlay(alignment: .bottom) { toastView }
        .task {
            // 화면 확인용: `--settings` 로 띄우면 설정 창을 연다.
            guard ProcessInfo.processInfo.arguments.contains("--settings") else { return }
            try? await Task.sleep(for: .milliseconds(800))
            openSettings()
        }
        .overlay { if !model.hasLoaded { LoadingView(progress: model.progress) } }
        .sheet(item: $model.report) { draft in ReportSheet(draft: draft) }
        .onChange(of: model.screen) { model.path = [] }
        .frame(minWidth: 960, minHeight: 640)
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = model.toast {
            Text(toast)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.cardBorder))
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// 오른쪽 본문. NavigationSplitView 의 detail 클로저 안에서 읽은 값은 변경 감지가 안 되어서,
/// 따로 떼어 낸 View 의 body 에서 모델을 읽는다.
struct DetailArea: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // NavigationStack 대신 열린 세션 목록(model.path)을 직접 보고 화면을 바꾼다.
        // 목록 화면은 지우지 않고 숨겨만 둬서, 돌아오면 스크롤 위치가 그대로다.
        ZStack {
            screen
                .opacity(model.path.isEmpty ? 1 : 0)
                .allowsHitTesting(model.path.isEmpty)
                .accessibilityHidden(!model.path.isEmpty)
            if let link = model.path.last {
                Group {
                    if let session = model.session(link.id) {
                        SessionDetailView(session: session)
                    } else {
                        EmptyHint(title: "세션을 찾을 수 없어요", message: "기록이 지워졌을 수 있어요.")
                    }
                }
                .id(link)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .navigationTitle(title.title)
        .navigationSubtitle(title.subtitle)
        .toolbar { toolbar }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        @Bindable var model = model
        if !model.path.isEmpty {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.path.removeLast()
                } label: {
                    Label("뒤로", systemImage: "chevron.left")
                }
                .keyboardShortcut("[", modifiers: .command)
                .help("이전 화면으로 (⌘[)")
            }
        }
        ToolbarItem(placement: .principal) {
            Picker("기간", selection: $model.period) {
                ForEach(Period.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("볼 기간")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(AITool.allCases) { tool in
                    Toggle(tool.displayName, isOn: Binding(
                        get: { model.tools.contains(tool) },
                        set: { on in
                            if on { model.tools.insert(tool) } else if model.tools.count > 1 { model.tools.remove(tool) }
                        }
                    ))
                }
                Divider()
                Toggle("자동 실행 세션도 보기", isOn: $model.includeAutomated)
            } label: {
                Label("필터", systemImage: model.tools.count < AITool.allCases.count || model.includeAutomated
                      ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .help("AI 도구 고르기")

            Button {
                model.makePeriodReport()
            } label: {
                Label("보고서", systemImage: "doc.text")
            }
            .help("지금 보는 기간의 작업을 마크다운 보고서로 만들기 (⌘E)")
            .disabled(model.days.isEmpty)

            Button {
                model.refresh()
            } label: {
                if model.isLoading && model.hasLoaded {
                    ProgressView().controlSize(.small)
                } else {
                    Label("새로 고침", systemImage: "arrow.clockwise")
                }
            }
            .help("기록 다시 읽기 (⌘R)")
            .disabled(model.isLoading)
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch model.screen ?? .dashboard {
        case .dashboard: DashboardView()
        case .timeline: TimelineView()
        case .prompts: PromptsView()
        case .skills: SkillsView()
        case .project(let path):
            if let project = model.project(path) {
                ProjectView(project: project)
                    .id(path)
            } else {
                EmptyHint(title: "이 조건에 맞는 기록이 없어요", message: "검색어나 도구 필터를 바꿔 보세요.", symbol: "folder")
            }
        }
    }

    private var title: (title: String, subtitle: String) {
        if let link = model.path.last, let s = model.session(link.id) { return (s.title, s.projectName) }
        switch model.screen ?? .dashboard {
        case .dashboard: return ("한눈에 보기", model.period.longLabel)
        case .timeline: return ("날짜별 기록", model.period.longLabel)
        case .prompts: return ("모든 요청", model.search.isEmpty ? "\(model.period.longLabel) · \(Fmt.number(model.totals.prompts))개" : "‘\(model.search)’ 검색")
        case .skills: return ("스킬·규칙", model.period.longLabel)
        case .project(let path): return (WorkSession.displayName(forPath: path), Fmt.path(path))
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.screen) {
            Section {
                Label("한눈에 보기", systemImage: "square.grid.2x2").tag(Screen.dashboard)
                Label("날짜별 기록", systemImage: "calendar").tag(Screen.timeline)
                    .badge(model.days.count)
                Label("모든 요청", systemImage: "text.bubble").tag(Screen.prompts)
                    .badge(model.totals.prompts)
                Label("스킬·규칙", systemImage: "wand.and.stars").tag(Screen.skills)
            }

            Section("프로젝트") {
                ForEach(model.projects) { project in
                    ProjectRow(project: project).tag(Screen.project(project.path))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var storeHelp: String {
        guard let st = model.snapshot.store else { return "보관함을 쓰지 않고 있어요" }
        var text = "보관함: 세션 \(st.sessions)개, 요청 \(st.prompts)개, \(ByteCountFormatter.string(fromByteCount: Int64(st.bytes), countStyle: .file))"
        if st.preserved > 0 { text += "\n원본이 지워졌지만 보관함에 남아 있는 세션 \(st.preserved)개" }
        if let url = model.storeURL { text += "\n\(Fmt.path(url.path))" }
        return text
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if model.isLoading {
                ProgressView().controlSize(.mini)
                Text("기록 읽는 중…")
            } else if model.hasLoaded {
                Image(systemName: "archivebox")
                Text("\(Fmt.time(model.snapshot.loadedAt)) 기준 · 보관함 세션 \(model.snapshot.sessions.count)개")
                    .help(storeHelp)
            }
            Spacer()
            if !model.snapshot.warnings.isEmpty {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help(model.snapshot.warnings.joined(separator: "\n"))
            }
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("설정: AI 요약, 자동 보관, 보관함 (⌘,)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

struct ProjectRow: View {
    var project: ProjectSummary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: project.sessions.isEmpty ? "folder.badge.questionmark" : "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name).lineLimit(1)
                Text(project.sessions.isEmpty ? "메모만 남음" : Fmt.relativeDay(project.lastActive))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                ForEach(AITool.chartOrder.filter(project.tools.contains)) { ToolBadge(tool: $0, compact: true) }
            }
        }
        .help(Fmt.path(project.path))
    }
}

struct LoadingView: View {
    var progress: Double?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.pages")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("AI 작업 기록을 읽고 있어요").font(.title3.weight(.semibold))
            Text("처음 한 번은 Claude Code·Codex 기록 전체를 읽어서 조금 걸려요.\n다음부터는 늘어난 부분만 읽어요.")
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let progress {
                ProgressView(value: progress).frame(width: 240)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
