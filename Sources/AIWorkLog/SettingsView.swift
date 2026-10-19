import SwiftUI
import WorkLogCore

/// 설정 창 (⌘,). 설치할 때 고르던 옵션을 앱 안에서도 켜고 끈다.
///   - 지난 날짜 AI 요약 미리 만들기  = `build_app.sh --install` (빼려면 `--no-summary`)
///   - 자동 보관                       = `build_app.sh --auto-sync` / `--remove-auto-sync`
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var autoSync = AutoSync().isEnabled
    @State private var autoSyncError: String?

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("요약에 쓸 AI", selection: $model.summaryChoice) {
                    Text("자동 (요즘 가장 많이 쓴 도구)").tag(SummaryChoice.auto)
                    ForEach(SummaryEngine.Kind.allCases) { kind in
                        Text(model.summaryEngineLabel(kind)).tag(SummaryChoice(kind))
                    }
                    Text("끄기").tag(SummaryChoice.off)
                }
                LabeledContent("지난 날짜 요약") {
                    backlogControl
                }
            } header: {
                Text("AI 날짜별 요약")
            } footer: {
                Text("설치할 때 하는 \"지난 날짜 모두 요약\"과 같아요. 한 번 만든 요약은 보관함에 남아서 다시 만들지 않아요. "
                     + (model.summaryEngine.map { "요약 재료는 \($0.destination)로 가요." } ?? ""))
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("앱을 열지 않아도 6시간마다 기록 모으기", isOn: Binding(get: { autoSync }, set: setAutoSync))
                if let error = autoSyncError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else if autoSync, let last = AutoSync().lastRun {
                    LabeledContent("마지막으로 모은 때", value: Fmt.dateTime(last))
                }
            } header: {
                Text("자동 보관")
            } footer: {
                Text("Claude Code 는 오래된 대화를 스스로 지워요. 켜 두면 앱을 오래 안 열어도 지워지기 전에 보관함에 옮겨 담아요. 설치할 때 --auto-sync 를 붙인 것과 같아요.")
                    .foregroundStyle(.secondary)
            }

            Section("보관함") {
                LabeledContent("모은 기록", value: storeSummary)
                if let url = model.storeURL {
                    LabeledContent("위치") {
                        HStack {
                            Text(Fmt.path(url.deletingLastPathComponent().path)).textSelection(.enabled)
                            Button("폴더 열기") { model.reveal(url.path) }
                        }
                    }
                }
                LabeledContent("원본 다시 읽기") {
                    Button("처음부터 다시 읽기") { model.refresh(rereadSources: true) }
                        .help("보관된 기록은 그대로 두고, 원본 기록 파일을 처음부터 다시 읽어요")
                }
            }
        }
        .formStyle(.grouped)
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
                Button("멈추기") { model.stopSummarizingAll() }
            }
        } else {
            let count = model.pastBacklogCount
            HStack(spacing: 8) {
                Text(count == 0 ? "모두 만들어 두었어요" : "아직 없거나 마감할 날 \(count)개")
                    .foregroundStyle(.secondary)
                Button("지금 모두 만들기") { model.summarizeAllPast() }
                    .disabled(count == 0 || model.summaryEngine == nil || model.isDemo)
            }
        }
    }

    private var storeSummary: String {
        let summaries = model.summaries.count
        guard let st = model.snapshot.store else { return "세션 \(model.snapshot.sessions.count)개 · 요약 \(summaries)개" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(st.bytes), countStyle: .file)
        return "세션 \(st.sessions)개 · 요청 \(Fmt.number(st.prompts))개 · 요약 \(summaries)개 · \(size)"
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
