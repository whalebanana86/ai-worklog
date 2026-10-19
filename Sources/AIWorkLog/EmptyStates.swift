import SwiftUI
import WorkLogCore

/// 한눈에 보기·날짜별 기록·모든 요청이 비었을 때 보여 주는 카드.
/// 왜 비었는지(모은 기록이 없음 → 검색어 → 도구 거르기 → 기간) 차례로 보고, 그에 맞는 안내와 버튼을 고른다.
struct NoRecordsCard: View {
    @Environment(AppModel.self) private var model
    /// "기록" 또는 "요청" (받침이 있는 낱말이라 뒤에 "이"를 붙인다)
    var noun = "기록"

    var body: some View {
        let query = model.search.trimmingCharacters(in: .whitespaces)
        // 기간만 빼고 같은 조건으로 마지막에 일한 때. 있으면 "다른 때에는 있어요"라고 알려 준다.
        let last = model.filtered.map(\.end).max()
        let allTools = model.tools.count == AITool.allCases.count

        if model.snapshot.sessions.isEmpty {
            EmptyCard(title: "아직 모은 AI 기록이 없어요",
                      message: "Claude Code·Codex·LM Studio 로 작업하면 여기에 날짜별로 모여요. 이 맥의 ~/.claude, ~/.codex, ~/.lmstudio 에서 기록을 읽어요.",
                      symbol: "tray") {
                Button("새로 고침") { model.refresh() }
            }
        } else if !query.isEmpty {
            EmptyCard(title: "‘\(query)’ 와 맞는 \(noun)이 없어요",
                      message: last.map { "\(model.period.longLabel)에는 없지만 다른 때에는 있어요. 마지막: \(Fmt.fullDay($0))" }
                          ?? "보낸 요청과 AI 답, 프로젝트 이름에서 찾지 못했어요.",
                      symbol: "magnifyingglass") {
                HStack {
                    Button("검색어 지우기") { model.search = "" }
                    if last != nil, model.period != .all { Button("전체 기간에서 찾기") { model.period = .all } }
                }
            }
        } else if model.filtered.isEmpty {
            EmptyCard(title: "고른 도구로 한 \(noun)이 없어요",
                      message: allTools ? "자동으로 돌린 세션만 있어요. 위쪽 거르기 메뉴에서 자동 실행 세션도 볼 수 있어요."
                          : "위쪽 거르기 메뉴에서 \(AITool.chartOrder.filter(model.tools.contains).map(\.displayName).joined(separator: "·"))만 보고 있어요.",
                      symbol: "line.3.horizontal.decrease.circle") {
                if !allTools {
                    Button("모든 도구 보기") { model.tools = Set(AITool.allCases) }
                } else if !model.includeAutomated {
                    Button("자동 실행 세션도 보기") { model.includeAutomated = true }
                }
            }
        } else {
            EmptyCard(title: "\(model.period.longLabel)에는 \(noun)이 없어요",
                      message: last.map { "마지막으로 일한 날: \(Fmt.fullDay($0))" } ?? "기간을 넓혀 보세요.",
                      symbol: "calendar") {
                if model.period != .all { Button("전체 기간 보기") { model.period = .all } }
            }
        }
    }
}

/// 목록 화면(날짜별 기록·모든 요청)에서 빈 카드를 한눈에 보기와 같은 자리·너비에 놓는다.
struct NoRecordsPage: View {
    var noun = "기록"

    var body: some View {
        ScrollView {
            NoRecordsCard(noun: noun)
                .padding(24)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
    }
}
