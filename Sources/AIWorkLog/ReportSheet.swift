import AppKit
import SwiftUI
import WorkLogCore
import UniformTypeIdentifiers

/// 마크다운 보고서를 보여 주고, 고치고, 복사하거나 파일로 저장한다.
struct ReportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var draft: ReportDraft
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.title).font(.headline)
                    Text(L("업무일지나 회고에 붙여 넣을 수 있게 마크다운으로 정리했어요. 여기서 바로 고쳐도 돼요."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            TextEditor(text: $text)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.cardBorder))
            HStack {
                Text(L("%@자", Fmt.number(text.count))).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("닫기")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("파일로 저장…")) { save() }
                Button(L("복사")) {
                    model.copy(text, message: L("보고서를 복사했어요"))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 720, height: 620)
        .onAppear { text = draft.markdown }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = draft.fileName
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            model.flash(L("%@ 로 저장했어요", url.lastPathComponent))
            dismiss()
        } catch {
            model.flash(L("저장하지 못했어요: %@", error.localizedDescription))
        }
    }
}
