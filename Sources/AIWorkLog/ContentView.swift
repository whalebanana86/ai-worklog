import SwiftUI
import WorkLogCore

@MainActor
struct ContentView: View {
    @Environment(AppModel.self) private var model
    #if compiler(>=6.0)
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        @Bindable var model = model
        let _ = model.language
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            DetailArea()
        }
        .searchable(text: $model.search, placement: .sidebar, prompt: L("요청·답변·프로젝트 검색"))
        // 언어를 바꾸면 화면 전체를 새로 그려 모든 글자를 새 언어로 다시 만든다. 차트 축의 날짜도 그 언어로.
        .id(model.language)
        .environment(\.locale, model.language.locale)
        .overlay(alignment: .bottom) { toastView }
        .task {
            // 화면 확인용: `--settings` 로 띄우면 설정 창을 연다.
            guard ProcessInfo.processInfo.arguments.contains("--settings") else { return }
            try? await Task.sleep(for: .milliseconds(800))
            #if compiler(>=6.0)
            openSettings()
            #else
            // Xcode 15 has SettingsLink but no OpenSettingsAction. Invoke the
            // standard Settings menu item so the SwiftUI Settings scene opens.
            if let menu = NSApp.mainMenu?.items.first?.submenu,
               let index = menu.items.firstIndex(where: {
                   $0.keyEquivalent == "," && $0.keyEquivalentModifierMask.contains(.command)
               }) {
                menu.performActionForItem(at: index)
            }
            #endif
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
@MainActor
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
                        EmptyHint(title: L("세션을 찾을 수 없어요"), message: L("기록이 지워졌을 수 있어요."))
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
                    Label(L("뒤로"), systemImage: "chevron.left")
                }
                .keyboardShortcut("[", modifiers: .command)
                .help(L("이전 화면으로 (⌘[)"))
            }
        }
        ToolbarItem(placement: .principal) {
            Picker(L("기간"), selection: $model.period) {
                ForEach(Period.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help(L("볼 기간"))
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
                Toggle(L("자동 실행 세션도 보기"), isOn: $model.includeAutomated)
            } label: {
                Label(L("필터"), systemImage: model.tools.count < AITool.allCases.count || model.includeAutomated
                      ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .help(L("AI 도구 고르기"))

            Button {
                model.makePeriodReport()
            } label: {
                Label(L("보고서"), systemImage: "doc.text")
            }
            .help(L("지금 보는 기간의 작업을 마크다운 보고서로 만들기 (⌘E)"))
            .disabled(model.days.isEmpty)

            Button {
                model.refresh()
            } label: {
                if model.isLoading && model.hasLoaded {
                    ProgressView().controlSize(.small)
                } else {
                    Label(L("새로 고침"), systemImage: "arrow.clockwise")
                }
            }
            .help(L("기록 다시 읽기 (⌘R)"))
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
                EmptyHint(title: L("이 조건에 맞는 기록이 없어요"), message: L("검색어나 도구 필터를 바꿔 보세요."), symbol: "folder")
            }
        }
    }

    private var title: (title: String, subtitle: String) {
        if let link = model.path.last, let s = model.session(link.id) { return (s.title, s.projectName) }
        switch model.screen ?? .dashboard {
        case .dashboard: return (L("한눈에 보기"), model.period.longLabel)
        case .timeline: return (L("날짜별 기록"), model.period.longLabel)
        case .prompts: return (L("모든 요청"), model.search.isEmpty ? L("%@ · %@개", model.period.longLabel, Fmt.number(model.totals.prompts)) : L("‘%@’ 검색", model.search))
        case .skills: return (L("스킬·규칙"), model.period.longLabel)
        case .project(let path): return (WorkSession.displayName(forPath: path), Fmt.path(path))
        }
    }
}

@MainActor
struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.screen) {
            Section {
                Label(L("한눈에 보기"), systemImage: "square.grid.2x2").tag(Screen.dashboard)
                Label(L("날짜별 기록"), systemImage: "calendar").tag(Screen.timeline)
                    .badge(model.days.count)
                Label(L("모든 요청"), systemImage: "text.bubble").tag(Screen.prompts)
                    .badge(model.totals.prompts)
                Label(L("스킬·규칙"), systemImage: "wand.and.stars").tag(Screen.skills)
            }

            Section(L("프로젝트")) {
                ForEach(model.projects) { project in
                    ProjectRow(project: project).tag(Screen.project(project.path))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var storeHelp: String {
        guard let st = model.snapshot.store else { return L("보관함을 쓰지 않고 있어요") }
        var text = L("보관함: 세션 %@개, 요청 %@개, %@", String(st.sessions), String(st.prompts),
                     ByteCountFormatter.string(fromByteCount: Int64(st.bytes), countStyle: .file))
        if st.preserved > 0 { text += "\n" + L("원본이 지워졌지만 보관함에 남아 있는 세션 %@개", String(st.preserved)) }
        if let url = model.storeURL { text += "\n\(Fmt.path(url.path))" }
        return text
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if model.isLoading {
                ProgressView().controlSize(.mini)
                Text(L("기록 읽는 중…"))
            } else if model.hasLoaded {
                Image(systemName: "archivebox")
                Text(L("%@ 기준 · 보관함 세션 %@개", Fmt.time(model.snapshot.loadedAt), String(model.snapshot.sessions.count)))
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
            .help(L("설정: AI 요약, 자동 보관, 보관함 (⌘,)"))
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
                Text(project.sessions.isEmpty ? L("메모만 남음") : Fmt.relativeDay(project.lastActive))
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
            Text(L("AI 작업 기록을 읽고 있어요")).font(.title3.weight(.semibold))
            Text(L("처음 한 번은 Claude Code·Codex 기록 전체를 읽어서 조금 걸려요.\n다음부터는 늘어난 부분만 읽어요."))
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
