import SwiftUI
import WorkLogCore

/// 설정 창 (⌘,). 설치할 때 고르던 옵션을 앱 안에서도 켜고 끈다.
///   - 지난 날짜 AI 요약 미리 만들기  = `build_app.sh --install` (빼려면 `--no-summary`)
///   - 자동 보관                       = `build_app.sh --auto-sync` / `--remove-auto-sync`
@MainActor
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var autoSync = AutoSync().isEnabled
    @State private var autoSyncError: String?
    private let colors = ToolColors.shared

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker(L("화면 언어"), selection: $model.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
            } header: {
                Text(L("언어"))
            } footer: {
                Text(L("바로 바뀌어요. 편집·윈도우 같은 macOS 기본 메뉴는 앱을 다시 열면 바뀌어요. 새로 만드는 AI 요약도 이 언어로 써요."))
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(AITool.allCases) { tool in
                    LabeledContent(tool.displayName) {
                        HStack(spacing: 8) {
                            if colors.isCustom(tool) {
                                Button(L("기본 색으로")) { colors.reset(tool) }
                            }
                            ColorPicker(tool.displayName, selection: Binding(get: { tool.color }, set: { colors.set($0, for: tool) }),
                                        supportsOpacity: false)
                                .labelsHidden()
                        }
                    }
                }
            } header: {
                Text(L("도구 색"))
            } footer: {
                Text(L("프로젝트 목록의 점, 차트, 도구 꼬리표에 쓰는 색이에요. 고른 색은 밝은 화면과 어두운 화면에 똑같이 써요."))
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(L("요약에 쓸 AI"), selection: $model.summaryChoice) {
                    Text(L("자동 (요즘 가장 많이 쓴 도구)")).tag(SummaryChoice.auto)
                    ForEach(SummaryEngine.Kind.allCases) { kind in
                        Text(model.summaryEngineLabel(kind)).tag(SummaryChoice(kind))
                    }
                    Text(L("끄기")).tag(SummaryChoice.off)
                }
                LabeledContent(L("찾은 AI 도구")) {
                    HStack(spacing: 8) {
                        Text(foundEngines).foregroundStyle(.secondary)
                        Button(L("다시 찾기")) { model.findSummaryEngines() }
                    }
                }
                LabeledContent(L("지난 날짜 요약")) {
                    backlogControl
                }
            } header: {
                Text(L("AI 날짜별 요약"))
            } footer: {
                Text(summaryFooter)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(L("앱을 열지 않아도 6시간마다 기록 모으기"), isOn: Binding(get: { autoSync }, set: setAutoSync))
                if let error = autoSyncError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else if autoSync, let last = AutoSync().lastRun {
                    LabeledContent(L("마지막으로 모은 때"), value: Fmt.dateTime(last))
                }
            } header: {
                Text(L("자동 보관"))
            } footer: {
                Text(L("Claude Code 는 오래된 대화를 스스로 지워요. 켜 두면 앱을 오래 안 열어도 지워지기 전에 보관함에 옮겨 담아요. 설치할 때 --auto-sync 를 붙인 것과 같아요."))
                    .foregroundStyle(.secondary)
            }

            Section(L("보관함")) {
                LabeledContent(L("모은 기록"), value: storeSummary)
                if let url = model.storeURL {
                    LabeledContent(L("위치")) {
                        HStack {
                            Text(Fmt.path(url.deletingLastPathComponent().path)).textSelection(.enabled)
                            Button(L("폴더 열기")) { model.reveal(url.path) }
                        }
                    }
                }
                LabeledContent(L("원본 다시 읽기")) {
                    Button(L("처음부터 다시 읽기")) { model.refresh(rereadSources: true) }
                        .help(L("보관된 기록은 그대로 두고, 원본 기록 파일을 처음부터 다시 읽어요"))
                }
            }
        }
        .formStyle(.grouped)
        .id(model.language)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { autoSync = AutoSync().isEnabled }
    }

    @ViewBuilder
    private var backlogControl: some View {
        if let progress = model.backlogProgress {
            HStack(spacing: 8) {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .frame(width: 120)
                Text("\(progress.done)/\(progress.total)").monospacedDigit().foregroundStyle(.secondary)
                Button(L("멈추기")) { model.stopSummarizingAll() }
            }
        } else {
            let count = model.pastBacklogCount
            HStack(spacing: 8) {
                Text(count == 0 ? L("모두 만들어 두었어요") : L("아직 없거나 마감할 날 %@개", String(count)))
                    .foregroundStyle(.secondary)
                Button(L("지금 모두 만들기")) { model.summarizeAllPast() }
                    .disabled(count == 0 || model.summaryEngine == nil || model.isDemo)
            }
        }
    }

    /// 한 식으로 이으면 오래된 컴파일러가 타입을 못 정해서 줄마다 나눠 쓴다.
    private var summaryFooter: String {
        var text = ""
        if model.summaryEngines?.isEmpty == true {
            text += L("요약할 AI 가 없어요. Claude Code·Codex 를 설치하거나 LM Studio 서버를 켜면 앱으로 돌아올 때 알아서 찾아요. 저장해 둔 요약은 그대로 보여요.\n")
        }
        text += L("설치할 때 하는 \"지난 날짜 모두 요약\"과 같아요. 한 번 만든 요약은 보관함에 남아서 다시 만들지 않아요. ")
        if let engine = model.summaryEngine { text += L("요약 재료는 %@로 가요.", engine.destination) }
        return text
    }

    private var foundEngines: String {
        guard let engines = model.summaryEngines else { return L("찾는 중…") }
        return engines.isEmpty ? L("없어요") : engines.map(\.displayName).joined(separator: " · ")
    }

    private var storeSummary: String {
        let summaries = model.summaries.count
        guard let st = model.snapshot.store else { return L("세션 %@개 · 요약 %@개", String(model.snapshot.sessions.count), String(summaries)) }
        let size = ByteCountFormatter.string(fromByteCount: Int64(st.bytes), countStyle: .file)
        return L("세션 %@개 · 요청 %@개 · 요약 %@개 · %@", String(st.sessions), Fmt.number(st.prompts), String(summaries), size)
    }

    private func setAutoSync(_ on: Bool) {
        autoSyncError = nil
        let sync = AutoSync()
        if on {
            do { try sync.enable() } catch { autoSyncError = "\(error)" }
        } else {
            sync.disable()
        }
        autoSync = sync.isEnabled
    }
}
