import SwiftUI
import WorkLogCore

/// 스킬·규칙 화면: 내가 만들어 둔 AI 설정과, 실제로 쓴 스킬·명령.
struct SkillsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let usage = WorkLogAnalytics.skillUsage(model.scoped)
        let scopes = projectScopes
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("스킬·규칙")).font(.system(size: 28, weight: .bold))
                    Text(summary(scopes: scopes, usage: usage)).font(.title3).foregroundStyle(.secondary)
                }

                Card(title: L("많이 쓴 스킬·명령"), subtitle: L("%@ · AI 가 부른 스킬과 내가 /이름 으로 부른 명령", model.period.longLabel)) {
                    if usage.isEmpty {
                        Text(L("이 기간에는 쓴 스킬·명령이 없어요")).foregroundStyle(.secondary)
                    } else {
                        SkillUsageList(usage: Array(usage.prefix(12)), definitions: definitions)
                    }
                }

                if !scopes.isEmpty {
                    Card(title: L("프로젝트별 설정"), subtitle: L("프로젝트 폴더에 만들어 둔 규칙·스킬·명령·서브에이전트·훅")) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(scopes.enumerated()), id: \.element.id) { index, scope in
                                ScopeSection(scope: scope, showProjectLink: true)
                                if index < scopes.count - 1 { Divider().padding(.vertical, 6) }
                            }
                        }
                    }
                }

                if !model.snapshot.globalConfigs.isEmpty {
                    Card(title: L("모든 프로젝트에 적용되는 설정"), subtitle: L("~/.claude, ~/.codex, 설치한 플러그인")) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(model.snapshot.globalConfigs.enumerated()), id: \.element.id) { index, scope in
                                ScopeSection(scope: scope, showProjectLink: false)
                                if index < model.snapshot.globalConfigs.count - 1 { Divider().padding(.vertical, 6) }
                            }
                        }
                    }
                }

                if model.snapshot.configs.isEmpty && model.snapshot.globalConfigs.isEmpty {
                    EmptyCard(title: model.snapshot.isSynced ? L("만들어 둔 스킬·규칙이 없어요") : L("설정을 찾는 중이에요"),
                              message: L("CLAUDE.md, AGENTS.md, .claude/skills 같은 파일을 찾아 보여 줘요."), symbol: "wand.and.stars")
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    /// 설정이 있는 폴더들. 최근에 작업한 프로젝트부터.
    private var projectScopes: [AIConfigScope] {
        let lastActive = Dictionary(model.projects.map { ($0.path, $0.lastActive) }, uniquingKeysWith: max)
        return model.snapshot.configs
            .map { AIConfigScope(title: WorkSession.displayName(forPath: $0.key), path: $0.key, items: $0.value) }
            .sorted { (lastActive[$0.path] ?? .distantPast, $1.path) > (lastActive[$1.path] ?? .distantPast, $0.path) }
    }

    /// 스킬 이름 → 정의 파일 (어디에 만들어 둔 스킬인지 보여 주려고).
    private var definitions: [String: AIConfigItem] {
        var map: [String: AIConfigItem] = [:]
        let all = model.snapshot.configs.values.flatMap { $0 } + model.snapshot.globalConfigs.flatMap(\.items)
        for item in all where item.kind == .skill || item.kind == .command {
            let key = item.name.hasPrefix("/") ? String(item.name.dropFirst()) : item.name
            if map[key] == nil { map[key] = item }
        }
        return map
    }

    private func summary(scopes: [AIConfigScope], usage: [(name: String, count: Int, projects: [String])]) -> String {
        let items = scopes.flatMap(\.items)
        let count = { (kind: AIConfigItem.Kind) in items.filter { $0.kind == kind }.count }
        var parts: [String] = []
        if count(.rule) > 0 { parts.append(L("규칙 %@개", String(count(.rule)))) }
        if count(.skill) > 0 { parts.append(L("스킬 %@개", String(count(.skill)))) }
        if count(.command) > 0 { parts.append(L("명령 %@개", String(count(.command)))) }
        if count(.agent) > 0 { parts.append(L("서브에이전트 %@개", String(count(.agent)))) }
        let made = parts.isEmpty ? L("프로젝트에 만들어 둔 설정은 없고") : L("폴더 %@곳에 %@를 만들어 두었고", String(scopes.count), parts.joined(separator: ", "))
        let used = usage.reduce(0) { $0 + $1.count }
        return L("%@, %@ 동안 스킬·명령을 %@번 썼어요.", made, model.period.longLabel, String(used))
    }
}

/// 스킬 사용 순위.
struct SkillUsageList: View {
    @Environment(AppModel.self) private var model
    var usage: [(name: String, count: Int, projects: [String])]
    var definitions: [String: AIConfigItem]

    var body: some View {
        let maxCount = usage.map(\.count).max() ?? 1
        VStack(alignment: .leading, spacing: 10) {
            ForEach(usage, id: \.name) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(row.name).font(.callout.monospaced().weight(.medium))
                        if let def = definitions[row.name] {
                            Text(def.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        } else {
                            Text(L("기본 제공 스킬")).font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(L("%@번", String(row.count))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.1))
                            Capsule().fill(Color.accentColor.opacity(0.85))
                                .frame(width: max(4, geo.size.width * Double(row.count) / Double(maxCount)))
                        }
                    }
                    .frame(height: 5)
                    Text(row.projects.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                .help(definitions[row.name].map { Fmt.path($0.path) } ?? L("Claude Code·플러그인에 들어 있는 스킬"))
            }
        }
    }
}

/// 설정을 찾은 폴더 하나와 그 안의 항목들.
struct ScopeSection: View {
    @Environment(AppModel.self) private var model
    var scope: AIConfigScope
    var showProjectLink: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                if showProjectLink, model.project(scope.path) != nil {
                    Button(scope.title) { model.show(project: scope.path) }
                        .buttonStyle(.link)
                        .font(.headline)
                } else {
                    Text(scope.title).font(.headline)
                }
                Text(Fmt.path(scope.path)).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                ForEach(AIConfigItem.Kind.allCases) { kind in
                    let n = scope.items.filter { $0.kind == kind }.count
                    if n > 0 { Chip(text: "\(kind.label) \(n)", symbol: kind.symbol) }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(AIConfigItem.Kind.allCases) { kind in
                    ForEach(scope.items.filter { $0.kind == kind }) { item in
                        ConfigItemRow(item: item)
                    }
                }
            }
            .padding(.leading, 22)
        }
        .padding(.vertical, 4)
    }
}

/// 설정 파일 한 줄. 누르면 내용 앞부분이 펼쳐진다.
struct ConfigItemRow: View {
    @Environment(AppModel.self) private var model
    var item: AIConfigItem
    @State private var expanded = false
    @State private var showFull = false

    private static let previewLimit = 3_000

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Image(systemName: item.kind.symbol).foregroundStyle(.secondary).frame(width: 16)
                    Text(item.name)
                        .font(item.kind == .rule || item.kind == .settings || item.kind == .mcp ? .callout.weight(.medium) : .callout.monospaced().weight(.medium))
                        .lineLimit(1)
                    Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 8)
                    if let origin = item.origin { Chip(text: origin, symbol: "shippingbox") }
                    if item.extraFiles > 0 { Text(L("참고 파일 %@", String(item.extraFiles))).font(.caption2).foregroundStyle(.tertiary) }
                    Text(Fmt.relativeDay(item.modified)).font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    MarkdownText(text: preview)
                        .font(.callout)
                    HStack(spacing: 8) {
                        if item.body.count > Self.previewLimit {
                            Button(L("전체 보기")) { showFull = true }
                        }
                        Button(L("Finder 에서 보기")) { model.reveal(item.path) }
                        Button(L("경로 복사")) { model.copy(item.path, message: L("경로를 복사했어요")) }
                    }
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                .padding(.leading, 24)
                .padding(.bottom, 6)
            }
        }
        .sheet(isPresented: $showFull) { ConfigDocumentSheet(item: item) }
    }

    private var preview: String {
        item.body.count > Self.previewLimit ? String(item.body.prefix(Self.previewLimit)) + "\n\n…" : item.body
    }
}

/// 긴 SKILL.md 전체. 화면에 보이는 부분만 그린다.
struct ConfigDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    var item: AIConfigItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.headline.monospaced())
                    Text(Fmt.path(item.path)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("닫기")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                MarkdownText(text: item.body, lazy: true)
                    .padding(.trailing, 8)
            }
        }
        .padding(20)
        .frame(width: 760, height: 640)
    }
}

/// 프로젝트 화면에 붙는 카드: 이 프로젝트에 걸린 AI 설정과 실제로 쓴 스킬.
struct ProjectConfigCard: View {
    @Environment(AppModel.self) private var model
    var project: ProjectSummary

    var body: some View {
        let scopes = WorkLogAnalytics.configScopes(for: project.path, configs: model.snapshot.configs)
        let used = project.skillsUsed.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        if !scopes.isEmpty || !used.isEmpty {
            Card(title: L("AI 규칙·스킬"), subtitle: L("이 프로젝트에서 AI 가 따르는 규칙과 쓸 수 있는 스킬·명령")) {
                if !used.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("이 프로젝트에서 쓴 스킬·명령")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(used, id: \.key) { name, count in
                                Chip(text: L("%@ %@번", name, String(count)), symbol: "wand.and.stars")
                            }
                        }
                    }
                    if !scopes.isEmpty { Divider() }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(scopes.enumerated()), id: \.element.id) { index, scope in
                        ScopeSection(scope: scope, showProjectLink: false)
                        if index < scopes.count - 1 { Divider().padding(.vertical, 6) }
                    }
                }
            }
        }
    }
}
