import Foundation

/// 업무일지·회고에 붙여 넣을 마크다운 보고서.
public enum ReportBuilder {
    public static func markdown(title: String, entries: [DayEntry], promptsPerSession: Int = 4, summary: DaySummary? = nil) -> String {
        let prompts = entries.reduce(0) { $0 + $1.userPrompts.count }
        var active = 0.0
        for e in entries {
            var clock = ActiveClock()
            for p in e.prompts { clock.tick(p.date) }
            active += e.prompts.isEmpty ? e.session.activeSeconds : clock.seconds
        }
        let added = entries.reduce(0) { $0 + $1.linesAdded }
        let removed = entries.reduce(0) { $0 + $1.linesRemoved }

        var out = "# \(title)\n\n"
        var stats = [L("세션 %@개", String(entries.count)), L("요청 %@개", Fmt.number(prompts)), L("작업 시간 약 %@", Fmt.duration(active))]
        if added + removed > 0 { stats.append(L("코드 약 +%@ / −%@줄", Fmt.number(added), Fmt.number(removed))) }
        out += "> " + stats.joined(separator: " · ") + "\n"
        if let ai = summary {
            out += "\n## " + L("한 일 요약") + "\n\n\(ai.headline)\n\n"
            for point in ai.points { out += "- \(point)\n" }
            out += "\n_" + L("%@ 가 요약함", ai.engine) + "_\n"
        }

        let byProject = Dictionary(grouping: entries, by: \.session.projectPath)
            .sorted { a, b in
                let ca = a.value.reduce(0) { $0 + $1.userPrompts.count }
                let cb = b.value.reduce(0) { $0 + $1.userPrompts.count }
                return ca == cb ? a.key < b.key : ca > cb
            }

        for (path, items) in byProject {
            out += "\n## \(WorkSession.displayName(forPath: path))\n"
            if !path.isEmpty, path.hasPrefix("/") { out += "`\(Fmt.path(path))`\n" }
            for e in items.sorted(by: { $0.firstDate < $1.firstDate }) {
                let s = e.session
                out += "\n### \(s.title)\n"
                var meta = ["\(s.tool.displayName)", Fmt.timeRange(e.firstDate, e.lastDate), L("요청 %@개", String(e.userPrompts.count))]
                let files = e.files
                if !files.isEmpty { meta.append(L("파일 %@개", String(files.count))) }
                if let b = s.gitBranch { meta.append(L("브랜치 `%@`", b)) }
                out += "- " + meta.joined(separator: " · ") + "\n"

                let asked = e.userPrompts.filter { !$0.isAutomated || e.userPrompts.count == 1 }
                if !asked.isEmpty {
                    out += L("- 요청한 일\n")
                    for p in asked.prefix(promptsPerSession) {
                        out += "  - \(p.text.plainLine.clipped(140))\n"
                    }
                    if asked.count > promptsPerSession { out += "  - …" + L("외 %@개", String(asked.count - promptsPerSession)) + "\n" }
                }
                if !files.isEmpty {
                    let names = files.prefix(6).map { "`\(Fmt.relativePath($0, to: s.projectPath))`" }
                    let more = files.count > 6 ? " " + L("외 %@개", String(files.count - 6)) : ""
                    out += L("- 고친 파일: ") + names.joined(separator: ", ") + more + "\n"
                }
                if let reply = e.prompts.last(where: { $0.reply != nil })?.reply {
                    out += L("- 마지막 결과: %@", reply.outcomeLine.clipped(220)) + "\n"
                }
            }
        }
        return out
    }
}
