import SwiftUI
import WorkLogCore

/// 날짜별로 그날 AI 와 한 작업.
@MainActor
struct TimelineView: View {
    @Environment(AppModel.self) private var model
    /// 무한 스크롤: 지금까지 그린 날 수.
    @State private var dayLimit = TimelineView.pageSize

    static let pageSize = 14

    var body: some View {
        Group {
            if model.days.isEmpty && model.hasLoaded {
                NoRecordsPage()
            } else {
                List {
                    ForEach(model.days.prefix(dayLimit)) { day in
                        Section {
                            ForEach(day.entries) { entry in
                                Button { model.open(entry.session) } label: { DayEntryRow(entry: entry) }
                                    .buttonStyle(.plain)
                            }
                        } header: {
                            DayHeader(day: day)
                        }
                    }
                    if model.days.count > dayLimit {
                        LoadMoreRow(remaining: model.days.count - dayLimit) { dayLimit += Self.pageSize }
                            .id(dayLimit)
                    }
                }
                .listStyle(.inset)
            }
        }
        .onChange(of: model.period) { dayLimit = Self.pageSize }
        .onChange(of: model.search) { dayLimit = Self.pageSize }
    }
}

@MainActor
struct DayHeader: View {
    @Environment(AppModel.self) private var model
    var day: DayGroup

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Fmt.relativeDay(day.day) == Fmt.day(day.day) ? Fmt.day(day.day) : "\(Fmt.relativeDay(day.day)) · \(Fmt.day(day.day))")
                .font(.headline)
                .foregroundStyle(.primary)
            Text(L("세션 %@ · 요청 %@ · %@", String(day.entries.count), String(day.promptCount), Fmt.duration(day.activeSeconds)))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                model.makeReport(day: day)
            } label: {
                Label(L("이날 보고서"), systemImage: "doc.text")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .help(L("이날 한 일을 마크다운으로 정리해요"))
        }
        .padding(.vertical, 4)
    }
}

struct DayEntryRow: View {
    var entry: DayEntry

    var body: some View {
        let s = entry.session
        let asked = entry.userPrompts
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.time(entry.firstDate)).font(.callout.monospacedDigit())
                if Fmt.time(entry.lastDate) != Fmt.time(entry.firstDate) {
                    Text("~ " + Fmt.time(entry.lastDate)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 52, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2).fill(s.tool.color).frame(width: 4)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(s.title).font(.body.weight(.medium)).lineLimit(1)
                    if !s.hasTranscript { Chip(text: L("요청만 남음"), symbol: "text.badge.minus") }
                    else if s.sourceMissing { Chip(text: L("보관본"), symbol: "archivebox") }
                    if s.isAutomated { Chip(text: L("자동 실행"), symbol: "gearshape") }
                }
                if let first = asked.first {
                    Text(first.text.singleLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // 이날 이 세션에서 AI 가 마지막으로 해낸 것
                if let outcome = entry.prompts.last(where: { $0.reply != nil })?.reply?.outcomeLine, !outcome.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "arrow.turn.down.right").font(.caption2)
                        Text(outcome).lineLimit(1)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ToolBadge(tool: s.tool)
                    Label(s.projectName, systemImage: "folder").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(L("요청 %@", String(asked.count))).font(.caption).foregroundStyle(.secondary)
                    if !entry.files.isEmpty {
                        Text(L("파일 %@", String(entry.files.count))).font(.caption).foregroundStyle(.secondary)
                        LineDelta(added: entry.linesAdded, removed: entry.linesRemoved)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// 기간 안에 보낸 모든 요청.
@MainActor
struct PromptsView: View {
    @Environment(AppModel.self) private var model
    /// 무한 스크롤: 지금까지 그린 요청 수.
    @State private var limit = PromptsView.pageSize

    static let pageSize = 60

    private struct Item: Identifiable {
        var session: WorkSession
        var prompt: PromptEntry
        var index: Int
        var id: String { "\(session.id)#\(index)" }
    }

    /// 검색 중이면 검색어가 요청이나 그 답변에 실제로 들어 있는 것만 남긴다 (세션 제목만 맞은 건 뺀다).
    private var items: [Item] {
        let query = model.search.trimmingCharacters(in: .whitespaces)
        func hit(_ text: String?) -> Bool { text?.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        return model.scoped
            .flatMap { s in s.prompts.enumerated().filter { !$0.element.isCommand }.map { Item(session: s, prompt: $0.element, index: $0.offset) } }
            .filter { query.isEmpty || hit($0.prompt.text) || hit($0.prompt.reply) }
            .sorted { $0.prompt.date > $1.prompt.date }
    }

    var body: some View {
        let items = self.items
        Group {
            if items.isEmpty && model.hasLoaded {
                NoRecordsPage(requests: true)
            } else {
                List {
                    ForEach(items.prefix(limit)) { item in
                    Button { model.open(item.session) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Fmt.relativeDay(item.prompt.date)).font(.caption).foregroundStyle(.secondary)
                                Text(Fmt.time(item.prompt.date)).font(.callout.monospacedDigit())
                            }
                            .frame(width: 64, alignment: .trailing)
                            RoundedRectangle(cornerRadius: 2).fill(item.session.tool.color).frame(width: 4)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(RichText.plain(item.prompt.text.singleLine, highlight: model.search)).lineLimit(3)
                                HStack(spacing: 6) {
                                    Text(item.session.projectName)
                                    Text("·")
                                    Text(item.session.title).lineLimit(1)
                                    if !item.prompt.files.isEmpty { Text(L("· 파일 %@", String(item.prompt.files.count))) }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    }
                    if items.count > limit {
                        LoadMoreRow(remaining: items.count - limit) { limit += Self.pageSize }
                            .id(limit)
                    }
                }
                .listStyle(.inset)
            }
        }
        .onChange(of: model.period) { limit = Self.pageSize }
        .onChange(of: model.search) { limit = Self.pageSize }
    }
}
