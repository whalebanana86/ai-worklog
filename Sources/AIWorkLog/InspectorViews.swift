import SwiftUI
import WorkLogCore

/// 오른쪽 정보 패널: 프로젝트의 자세한 숫자와 폴더 동작.
/// 위에는 위쪽 기간 버튼에 맞춘 숫자, 아래에는 전체 기간 숫자 (전체 기간을 고르면 아래 하나만).
@MainActor
struct ProjectInspector: View {
    @Environment(AppModel.self) private var model
    var project: ProjectSummary

    var body: some View {
        Form {
            if model.period != .all, !project.sessions.isEmpty {
                let p = project.totals(in: model.period.interval())
                Section(model.period.longLabel) {
                    if p.totals.prompts == 0 {
                        Text(L("이 기간에는 AI 에게 맡긴 일이 없어요."))
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent(L("작업 시간"), value: Fmt.duration(p.totals.activeSeconds))
                        LabeledContent(L("세션")) {
                            HStack(spacing: 6) {
                                ForEach(AITool.chartOrder.filter(p.tools.contains)) { ToolBadge(tool: $0, compact: true) }
                                Text(Fmt.number(p.totals.sessions))
                            }
                        }
                        LabeledContent(L("요청"), value: Fmt.number(p.totals.prompts))
                        LabeledContent(L("작업한 날"), value: L("%@일", String(p.totals.activeDays)))
                    }
                }
            }
            Section(L("전체 기간")) {
                LabeledContent(L("작업 시간"), value: Fmt.duration(project.activeSeconds))
                LabeledContent(L("세션")) {
                    HStack(spacing: 6) {
                        ForEach(AITool.chartOrder.filter(project.tools.contains)) { ToolBadge(tool: $0, compact: true) }
                        Text(Fmt.number(project.sessions.count))
                    }
                }
                LabeledContent(L("요청"), value: Fmt.number(project.promptCount))
                if !project.sessions.isEmpty {
                    LabeledContent(L("처음 작업"), value: Fmt.day(project.firstActive))
                    LabeledContent(L("마지막 작업"), value: Fmt.dateTime(project.lastActive))
                }
            }
            if project.path.hasPrefix("/") {
                Section(L("위치")) {
                    Text(Fmt.path(project.path))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    ProjectMenuItems(path: project.path)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// 오른쪽 정보 패널: 세션의 자세한 숫자와 모델별 토큰.
@MainActor
struct SessionInspector: View {
    var session: WorkSession

    var body: some View {
        Form {
            Section {
                LabeledContent(L("작업 시간")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Fmt.duration(session.activeSeconds))
                        Text(Fmt.timeRange(session.start, session.end)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent(L("요청"), value: Fmt.number(session.userPrompts.count))
                LabeledContent(L("고친 파일"), value: Fmt.number(session.files.count))
                LabeledContent(L("코드 변경")) {
                    LineDelta(added: session.linesAdded ?? 0, removed: session.linesRemoved ?? 0)
                }
                if let cost = session.costUSD { LabeledContent(L("비용"), value: Fmt.cost(cost)) }
                LabeledContent(L("토큰"), value: Fmt.compact(session.totalTokens))
            } header: {
                HStack(spacing: 6) { ToolBadge(tool: session.tool); Spacer() }
            }
            let models = session.models.sorted { $0.value.totalTokens > $1.value.totalTokens }
            if !models.isEmpty {
                Section(L("모델")) {
                    ForEach(models, id: \.key) { name, usage in
                        LabeledContent { Text(Fmt.compact(usage.totalTokens)) } label: {
                            Text(name).font(.callout.monospaced()).lineLimit(1)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
