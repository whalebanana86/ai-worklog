import Charts
import SwiftUI
import WorkLogCore

@MainActor
struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if model.scoped.isEmpty && model.hasLoaded {
                    NoRecordsCard()
                } else {
                    kpis
                    Card(title: model.period == .today ? L("시간대별 요청") : L("날짜별 요청"),
                         subtitle: L("막대에 마우스를 올리면 도구별 수가 보여요")) {
                        ActivityChart(sessions: model.scoped, period: model.period)
                            .frame(height: 210)
                    }
                    CardPair {
                        Card(title: L("프로젝트별 작업 시간"), subtitle: L("AI 가 일한 시간 포함"), fillHeight: true) {
                            ProjectBars(times: Array(WorkLogAnalytics.projectTimes(model.days).prefix(8)))
                        }
                    } second: {
                        Card(title: L("언제 일했나"), subtitle: L("요일·시간대별 요청 수"), fillHeight: true) {
                            WeekHourHeatmap(grid: WorkLogAnalytics.weekHourGrid(model.scoped))
                        }
                    }
                    recent
                    CardPair {
                        toolsCard
                    } second: {
                        modelsCard
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            PageHeader(title: L("한눈에 보기"), summary: "\(model.period.longLabel) · \(summarySentence)")
            // 기록이 없을 때는 아래 빈 카드에 모아가 따로 나온다.
            if !model.scoped.isEmpty { MascotView(pose: mood, cell: 2) }
        }
    }

    /// 지난 기간보다 작업 시간이 늘었으면 뿌듯한 모아. 견줄 기간이 없으면(전체) 평소 모습.
    private var mood: Mascot.Pose {
        guard let before = model.previousTotals?.activeSeconds else { return .idle }
        return model.totals.activeSeconds > before ? .proud : .idle
    }

    private var summarySentence: String {
        let t = model.totals
        guard t.prompts > 0 else { return model.snapshot.sessions.isEmpty ? L("아직 AI 에게 맡긴 일이 없어요.") : L("이 기간에는 AI 에게 맡긴 일이 없어요.") }
        return L("프로젝트 %@곳에서 AI 에게 %@번 요청하고, 약 %@ 함께 작업했어요.", String(t.projects), Fmt.number(t.prompts), Fmt.duration(t.activeSeconds))
    }

    private var kpis: some View {
        let t = model.totals
        let p = model.previousTotals
        func trend(_ now: Double, _ before: Double?) -> String? { Trend.text(now, before, versus: model.period.previousLabel) }
        return TileRows(tiles: [
            StatTile(label: L("작업 시간"), value: Fmt.duration(t.activeSeconds), caption: L("AI 가 일한 시간 포함"), symbol: "clock",
                     trend: trend(t.activeSeconds, p?.activeSeconds)),
            StatTile(label: L("요청"), value: Fmt.number(t.prompts), caption: L("세션 %@개", Fmt.number(t.sessions)), symbol: "text.bubble",
                     trend: trend(Double(t.prompts), p.map { Double($0.prompts) })),
            StatTile(label: L("작업한 날"), value: L("%@일", String(t.activeDays)), caption: L("프로젝트 %@곳", String(t.projects)), symbol: "calendar",
                     trend: trend(Double(t.activeDays), p.map { Double($0.activeDays) })),
            StatTile(label: L("고친 파일"), value: Fmt.number(t.files), caption: L("+%@ / −%@줄 (어림)", Fmt.compact(t.linesAdded), Fmt.compact(t.linesRemoved)), symbol: "doc.badge.ellipsis",
                     trend: trend(Double(t.files), p.map { Double($0.files) })),
            StatTile(label: L("사용 비용"), value: t.costUSD > 0 ? Fmt.cost(t.costUSD) : "–", caption: L("Claude Code 기록 기준"), symbol: "dollarsign.circle",
                     trend: trend(t.costUSD, p?.costUSD)),
            StatTile(label: L("토큰"), value: Fmt.compact(t.tokens), caption: L("캐시 읽기 포함"), symbol: "number",
                     trend: trend(Double(t.tokens), p.map { Double($0.tokens) })),
        ])
    }

    private var recent: some View {
        Card(title: L("최근 작업")) {
            let items = Array(model.scoped.prefix(6))
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, session in
                    Button { model.open(session) } label: { SessionRow(session: session) }
                        .buttonStyle(.plain)
                        .contextMenu { SessionMenuItems(session: session) }
                    if index < items.count - 1 { Divider() }
                }
            }
            if model.scoped.count > 6 {
                Button(L("날짜별 기록에서 모두 보기 →")) { model.screen = .timeline }
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
    }

    private var toolsCard: some View {
        Card(title: L("AI 가 많이 쓴 도구"), subtitle: L("이 기간에 걸친 세션 전체 기준"), fillHeight: true) {
            let tools = WorkLogAnalytics.toolTotals(model.scoped).prefix(14)
            if tools.isEmpty {
                Text(L("도구 기록이 없어요")).foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(Array(tools), id: \.name) { item in
                        Chip(text: "\(ToolLabel.label(item.name)) \(Fmt.compact(item.count))", symbol: ToolLabel.symbol(item.name))
                    }
                }
            }
        }
    }

    private var modelsCard: some View {
        Card(title: L("모델별 사용량"), subtitle: L("이 기간에 걸친 세션 전체 기준"), fillHeight: true) {
            let rows = WorkLogAnalytics.modelTotals(model.scoped).prefix(6)
            if rows.isEmpty {
                Text(L("모델 기록이 없어요")).foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text(L("모델")); Text(L("세션")).gridColumnAlignment(.trailing); Text(L("토큰")).gridColumnAlignment(.trailing); Text(L("비용")).gridColumnAlignment(.trailing)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(Array(rows)) { row in
                        GridRow {
                            Text(row.model).font(.callout.monospaced()).lineLimit(1)
                            Text(Fmt.number(row.sessions))
                            Text(Fmt.compact(row.tokens))
                            Text(row.costUSD.map(Fmt.cost) ?? "–")
                        }
                        .font(.callout.monospacedDigit())
                    }
                }
            }
        }
    }
}

/// 세션 한 줄 요약. 대시보드·프로젝트 화면에서 같이 쓴다.
struct SessionRow: View {
    var session: WorkSession
    var promptsOverride: [PromptEntry]?

    var body: some View {
        let prompts = (promptsOverride ?? session.prompts).filter { !$0.isCommand }
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(session.tool.color)
                .frame(width: 4)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.title).font(.body.weight(.medium)).lineLimit(1)
                    if !session.hasTranscript {
                        Chip(text: L("요청만 남음"), symbol: "text.badge.minus").help(L("대화 원본은 지워지고 입력한 요청 기록만 남은 세션이에요"))
                    } else if session.sourceMissing {
                        Chip(text: L("보관본"), symbol: "archivebox").help(L("원본은 지워졌지만 이 앱 보관함에 남아 있어요"))
                    }
                }
                HStack(spacing: 8) {
                    ToolBadge(tool: session.tool)
                    Text(session.projectName).font(.caption).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(L("요청 %@", String(prompts.count))).font(.caption).foregroundStyle(.secondary)
                    if !session.files.isEmpty {
                        Text(L("· 파일 %@", String(session.files.count))).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Fmt.relativeDay(session.end)).font(.caption).foregroundStyle(.secondary)
                Text(Fmt.duration(session.activeSeconds)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - 차트

@MainActor
struct ActivityChart: View {
    var sessions: [WorkSession]
    var period: Period
    /// 막대를 눌렀을 때 그 날(시간대)을 알려 준다. nil 이면 누를 수 없다.
    var onPick: ((Date) -> Void)? = nil
    /// 눌러서 고른 날. 그 막대만 진하게 보인다.
    var picked: Date? = nil
    @State private var hovered: Date? = LaunchOptions.hoverDay

    private struct Bucket: Identifiable {
        var date: Date
        var tool: AITool
        var count: Int
        var id: String { "\(date.timeIntervalSince1970)-\(tool.rawValue)" }
    }

    private var unit: Calendar.Component { period == .today ? .hour : .day }
    /// 막대 너비 (한 칸 대비). 마우스를 올린 띠·고른 날 띠도 같은 너비로 그려 기간이 바뀌어도 막대와 맞는다.
    private static let barRatio = 0.7

    private var buckets: [Bucket] {
        let cal = Calendar.current
        var map: [Date: [AITool: Int]] = [:]
        for s in sessions {
            for p in s.prompts where !p.isCommand {
                let key = unit == .hour ? cal.dateInterval(of: .hour, for: p.date)!.start : cal.startOfDay(for: p.date)
                map[key, default: [:]][s.tool, default: 0] += 1
            }
        }
        return map.flatMap { date, tools in tools.map { Bucket(date: date, tool: $0.key, count: $0.value) } }
            .sorted { ($0.date, AITool.chartOrder.firstIndex(of: $0.tool) ?? 0) < ($1.date, AITool.chartOrder.firstIndex(of: $1.tool) ?? 0) }
    }

    private var domain: ClosedRange<Date> {
        let cal = Calendar.current
        let now = Date()
        if period == .today {
            let start = cal.startOfDay(for: now)
            return start...cal.date(byAdding: .hour, value: 24, to: start)!
        }
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        let start: Date
        if let days = period.days {
            start = cal.date(byAdding: .day, value: -days, to: end)!
        } else {
            start = buckets.first.map { cal.startOfDay(for: $0.date) } ?? cal.date(byAdding: .day, value: -30, to: end)!
        }
        return start...end
    }

    var body: some View {
        let data = buckets
        let tools = AITool.chartOrder.filter { t in data.contains { $0.tool == t } }
        VStack(alignment: .leading, spacing: 8) {
            // 범례를 차트 밖에 두어야 툴팁이 범례를 덮지 않는다.
            if tools.count > 1 {
                HStack(spacing: 14) {
                    ForEach(tools) { tool in
                        HStack(spacing: 5) {
                            Circle().fill(tool.color).frame(width: 8, height: 8)
                            Text(tool.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            chart(data: data, tools: tools)
        }
    }

    private func chart(data: [Bucket], tools: [AITool]) -> some View {
        Chart {
            ForEach(data) { b in
                BarMark(x: .value(L("날짜"), b.date, unit: unit), y: .value(L("요청"), b.count), width: .ratio(Self.barRatio))
                    .foregroundStyle(by: .value(L("도구"), b.tool.displayName))
                    .cornerRadius(2)
            }
            // 마우스를 올린 막대 뒤의 옅은 띠. 툴팁은 여기 붙이지 않는다(붙이면 같이 막대 뒤로 깔린다).
            // 두께를 고정한 선 대신 칸 비율로 그린 띠라서 7일(넓은 막대)·90일(좁은 막대)에도 막대 너비와 같다.
            if let hovered {
                RectangleMark(x: .value(L("선택"), hovered, unit: unit), width: .ratio(Self.barRatio))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                    .cornerRadius(2)
                    .zIndex(-1)
            }
            if let picked {
                RectangleMark(x: .value(L("고른 날"), picked, unit: unit), width: .ratio(Self.barRatio))
                    .foregroundStyle(Color.accentColor.opacity(0.18))
                    .cornerRadius(2)
                    .zIndex(-1)
            }
        }
        .chartForegroundStyleScale(domain: tools.map(\.displayName), range: tools.map(\.color))
        .chartLegend(.hidden)
        .chartXScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.axisInk.opacity(0.35))
                AxisValueLabel().foregroundStyle(Color.axisInk)
            }
        }
        .chartXAxis {
            if unit == .hour {
                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                    AxisValueLabel(centered: false) {
                        if let d = value.as(Date.self) { Text(L("%@시", String(Calendar.current.component(.hour, from: d)))) }
                    }
                    .foregroundStyle(Color.axisInk)
                }
            } else {
                AxisMarks(values: .automatic(desiredCount: 7)) { value in
                    AxisValueLabel(centered: true) {
                        if let d = value.as(Date.self) { Text(Fmt.shortDay(d)) }
                    }
                    .foregroundStyle(Color.axisInk)
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let frame = proxy.plotFrame.map { geo[$0] } ?? .zero
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        // 시연 영상(--tour)에서는 실제 마우스 자리에 따라 툴팁이 뜨지 않게.
                        case .active(let location): hovered = LaunchOptions.isTour ? nil : bucketDate(at: location, proxy: proxy, frame: frame)
                        case .ended: hovered = nil
                        }
                    }
                    .onTapGesture { location in
                        if let onPick, let date = bucketDate(at: location, proxy: proxy, frame: frame) { onPick(date) }
                    }
                    // 툴팁은 차트 맨 위 층(덧씌우기)에 따로 그린다. 덧씌우기라 아래 판의 자리는 건드리지 않는다.
                    // 오른쪽 끝에 가까우면 막대 왼쪽에 띄운다.
                    .overlay(alignment: .topLeading) {
                        if let hovered, let x = proxy.position(forX: hovered.addingTimeInterval(unit == .hour ? 1800 : 43_200)) {
                            let barX = frame.minX + x
                            let width = Self.tooltipWidth
                            let gap: CGFloat = 14
                            let fitsRight: Bool = barX + gap + width <= frame.maxX
                            let left: CGFloat = fitsRight ? barX + gap : barX - gap - width
                            tooltip(for: hovered, data: data)
                                .frame(width: width, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .offset(x: max(0, left), y: frame.minY + 2)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    static let tooltipWidth: CGFloat = 180

    /// 마우스 위치의 날(또는 시간대) 시작 시각.
    private func bucketDate(at location: CGPoint, proxy: ChartProxy, frame: CGRect) -> Date? {
        guard frame.contains(CGPoint(x: location.x, y: frame.midY)),
              let date: Date = proxy.value(atX: location.x - frame.minX) else { return nil }
        let cal = Calendar.current
        return unit == .hour ? cal.dateInterval(of: .hour, for: date)?.start : cal.startOfDay(for: date)
    }

    private func tooltip(for date: Date, data: [Bucket]) -> some View {
        let rows = data.filter { $0.date == date }
        let total = rows.reduce(0) { $0 + $1.count }
        return VStack(alignment: .leading, spacing: 4) {
            Text(unit == .hour ? "\(Fmt.time(date)) ~ \(Fmt.time(date.addingTimeInterval(3600)))" : Fmt.day(date))
                .font(.caption.weight(.semibold))
            if onPick != nil && !rows.isEmpty {
                Text(L("누르면 그날 한 일만 보기")).font(.caption2).foregroundStyle(.tertiary)
            }
            if rows.isEmpty {
                Text(L("요청 없음")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(rows) { r in
                    HStack(spacing: 6) {
                        Circle().fill(r.tool.color).frame(width: 7, height: 7)
                        Text(r.tool.displayName).foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Text("\(r.count)").monospacedDigit()
                    }
                    .font(.caption)
                }
                if rows.count > 1 {
                    Divider()
                    HStack { Text(L("합계")).foregroundStyle(.secondary); Spacer(); Text("\(total)").monospacedDigit() }.font(.caption)
                }
            }
        }
        .padding(8)
        // 막대가 비쳐 글자가 묻히지 않게 불투명한 바탕.
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.cardBorder))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}

/// 숫자 칸들: 넓으면 한 줄, 좁으면 반씩 두 줄.
struct TileRows: View {
    var tiles: [StatTile]

    var body: some View {
        // 넓으면 한 줄, 좁아지면 두 줄, 더 좁으면 두 칸씩 (사이드바·정보 패널을 넓혀 본문이 좁아질 때).
        ViewThatFits(in: .horizontal) {
            row(tiles[...])
            VStack(spacing: 12) {
                row(tiles.prefix((tiles.count + 1) / 2))
                row(tiles.dropFirst((tiles.count + 1) / 2))
            }
            VStack(spacing: 12) {
                ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { start in
                    row(tiles[start..<min(start + 2, tiles.count)])
                }
            }
        }
    }

    private func row(_ items: ArraySlice<StatTile>) -> some View {
        // 설명 줄이 있는 칸과 없는 칸의 높이를 맞춘다.
        HStack(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, tile in tile.frame(minWidth: 150) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 순위형 가로 막대. 값이 바로 옆에 적혀 있어 따로 툴팁이 필요 없다.
@MainActor
struct ProjectBars: View {
    @Environment(AppModel.self) private var model
    var times: [ProjectTime]

    var body: some View {
        if times.isEmpty {
            Text(L("기록이 없어요")).foregroundStyle(.secondary)
        } else {
            let maxSeconds = times.map(\.seconds).max() ?? 1
            VStack(alignment: .leading, spacing: 10) {
                ForEach(times) { t in
                    Button { model.show(project: t.path) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(t.name).font(.callout).lineLimit(1)
                                Spacer()
                                Text(L("%@ · 요청 %@", Fmt.duration(t.seconds), String(t.prompts)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.secondary.opacity(0.1))
                                    Capsule().fill(Color.accentColor.opacity(0.85))
                                        .frame(width: max(4, geo.size.width * t.seconds / maxSeconds))
                                }
                            }
                            .frame(height: 6)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("%@ 프로젝트 보기", Fmt.path(t.path)))
                }
            }
        }
    }
}

struct WeekHourHeatmap: View {
    /// [요일 0=일요일][시]
    var grid: [[Int]]

    private let order = [1, 2, 3, 4, 5, 6, 0]
    private let names = [L("일"), L("월"), L("화"), L("수"), L("목"), L("금"), L("토")]

    var body: some View {
        let maxValue = max(grid.flatMap { $0 }.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 3) {
            ForEach(order, id: \.self) { w in
                HStack(spacing: 3) {
                    Text(names[w]).font(.caption2).foregroundStyle(.secondary).frame(width: 20, alignment: .leading)
                    ForEach(0..<24, id: \.self) { h in
                        let v = grid[w][h]
                        RoundedRectangle(cornerRadius: 2)
                            .fill(v == 0 ? Color.secondary.opacity(0.08) : Color.heat(level(v, maxValue)))
                            .aspectRatio(1, contentMode: .fit)
                            .help(L("%@요일 %@시 · 요청 %@개", names[w], String(h), String(v)))
                    }
                }
            }
            HStack(spacing: 3) {
                Spacer().frame(width: 16)
                ForEach(0..<24, id: \.self) { h in
                    // 칸이 좁아도 "12" 가 두 줄로 쪼개지지 않게 옆 칸으로 넘치게 둔다.
                    Text(h % 6 == 0 ? L("%@시", String(h)) : "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(spacing: 4) {
                Spacer()
                Text(L("적음")).font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(Color.heat(i)).frame(width: 10, height: 10)
                }
                Text(L("많음")).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private func level(_ v: Int, _ maxValue: Int) -> Int {
        Int((Double(v) / Double(maxValue) * 5).rounded(.up)).clamped(0, 5)
    }
}

extension Int {
    func clamped(_ lo: Int, _ hi: Int) -> Int { Swift.max(lo, Swift.min(hi, self)) }
}

/// AI 도구 이름을 알아보기 쉽게.
enum ToolLabel {
    /// 화면에 쓰는 도구 이름. Codex 기록의 한국어 이름("파일 수정")은 보관함에 그대로 두고 보여 줄 때만 번역한다.
    static func label(_ name: String) -> String {
        switch name {
        case "Bash": return L("터미널 명령")
        case "Read": return L("파일 읽기")
        case "Edit", "MultiEdit": return L("파일 수정")
        case "Write": return L("파일 쓰기")
        case "Grep": return L("내용 검색")
        case "Glob": return L("파일 찾기")
        case "WebSearch": return L("웹 검색")
        case "WebFetch": return L("웹 페이지 읽기")
        case "Agent", "Task": return L("서브에이전트")
        case "TodoWrite": return L("할 일 목록")
        case "Skill": return L("스킬")
        case "ToolSearch": return L("도구 불러오기")
        case "AskUserQuestion": return L("질문하기")
        case "NotebookEdit": return L("노트북 수정")
        default: return L(name)
        }
    }

    /// 보관함에 저장된 도구 이름(Codex 는 한국어 이름)과 견주니 번역하지 않는다.
    static func symbol(_ name: String) -> String {
        switch name {
        case "Bash", "명령 실행": return "terminal"
        case "Read", "이미지 보기": return "eye"
        case "Edit", "MultiEdit", "Write", "NotebookEdit", "파일 수정": return "pencil"
        case "Grep", "Glob": return "magnifyingglass"
        case "WebSearch", "WebFetch", "웹 검색": return "globe"
        case "Agent", "Task": return "person.2"
        case "TodoWrite": return "checklist"
        case "이미지 생성": return "photo"
        default: return name.hasPrefix("MCP") ? "puzzlepiece.extension" : "wrench.and.screwdriver"
        }
    }
}
