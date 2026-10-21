import SwiftUI
import WorkLogCore

/// 세션 줄의 오른쪽 클릭 메뉴. 요청 줄에서 열면 그 요청 복사도 넣는다.
@MainActor
struct SessionMenuItems: View {
    @Environment(AppModel.self) private var model
    var session: WorkSession
    var prompt: PromptEntry? = nil

    var body: some View {
        Button(L("세션 열기")) { model.open(session) }
        if let prompt {
            Button(L("요청 복사")) { model.copy(prompt.text, message: L("요청을 복사했어요")) }
        }
        if session.projectPath.hasPrefix("/") {
            Button(L("프로젝트로 가기")) { model.show(project: session.projectPath) }
        }
        Divider()
        if session.hasTranscript, let command = session.tool.resumeCommand(sessionId: session.sessionId, cwd: session.cwd) {
            Button(L("이어서 작업하기")) { model.copy(command, message: L("터미널에 붙여 넣으면 이 대화를 이어서 할 수 있어요")) }
        }
        if let folder = folder {
            Button(L("터미널 열기")) { model.openTerminal(at: folder) }
            Button(L("Finder 에서 보기")) { model.reveal(folder) }
        }
    }

    private var folder: String? {
        if session.projectPath.hasPrefix("/") { return session.projectPath }
        return session.cwd.hasPrefix("/") ? session.cwd : nil
    }
}

/// 프로젝트(사이드바 줄·프로젝트 화면 머리)의 메뉴.
@MainActor
struct ProjectMenuItems: View {
    @Environment(AppModel.self) private var model
    var path: String

    var body: some View {
        if path.hasPrefix("/") {
            Button { model.reveal(path) } label: { Label(L("Finder 에서 열기"), systemImage: "folder") }
            Button { model.openTerminal(at: path) } label: { Label(L("터미널 열기"), systemImage: "terminal") }
            Button { model.copy(path, message: L("경로를 복사했어요")) } label: { Label(L("경로 복사"), systemImage: "doc.on.doc") }
        }
    }
}

/// 그 전 같은 기간과 견준 변화를 한 줄로: "▲ 12% · 그 전 30일 대비".
enum Trend {
    static func text(_ now: Double, _ before: Double?, versus label: String?) -> String? {
        guard let before, let label, now > 0 || before > 0 else { return nil }
        guard before > 0 else { return L("%@엔 없었어요", label) }
        let change = (now - before) / before * 100
        let rounded = Int(change.rounded())
        let mark = rounded == 0 ? L("변화 없음") : (rounded > 0 ? "▲ " : "▼ ") + Fmt.number(abs(rounded)) + "%"
        return L("%@ · %@ 대비", mark, label)
    }
}
