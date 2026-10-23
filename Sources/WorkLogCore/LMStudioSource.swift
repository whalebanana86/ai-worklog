import Foundation

/// LM Studio 로컬 모델과 나눈 대화(~/.lmstudio/conversations/*.conversation.json).
public struct LMStudioSource {
    public let root: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lmstudio/conversations")) {
        self.root = root
    }

    public func load() -> [WorkSession] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var sessions: [WorkSession] = []
        for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".conversation.json") {
            if let s = parse(url) { sessions.append(s) }
        }
        return sessions
    }

    func parse(_ url: URL) -> WorkSession? {
        guard let data = try? Data(contentsOf: url),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let created = (o["createdAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? modified
        let model = ((o["lastUsedModel"] as? [String: Any])?["identifier"] as? String) ?? "local-model"

        // 메시지는 여러 버전(다시 생성)을 가질 수 있어서, 고른 버전만 본다.
        var prompts: [PromptEntry] = []
        for message in (o["messages"] as? [[String: Any]]) ?? [] {
            var version = message
            if let versions = message["versions"] as? [[String: Any]], !versions.isEmpty {
                let index = min((message["currentlySelectedVersion"] as? Int) ?? 0, versions.count - 1)
                version = versions[index]
            }
            let text = Self.texts(in: version).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            switch version["role"] as? String {
            case "user":
                prompts.append(PromptEntry(date: created, text: text.clipped(ClaudeAccumulator.promptLimit)))
            case "assistant":
                if !prompts.isEmpty { prompts[prompts.count - 1].reply = text.clipped(ClaudeAccumulator.replyLimit) }
            default:
                break
            }
        }
        guard let first = prompts.first else { return nil }

        let name = (o["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkSession(
            tool: .lmStudio,
            sessionId: url.deletingPathExtension().deletingPathExtension().lastPathComponent,
            title: (name?.isEmpty == false ? name! : first.text.singleLine).clipped(80),
            cwd: "",
            projectPath: "LM Studio 대화",
            start: created,
            end: max(created, modified),
            prompts: prompts,
            models: [model: ModelUsage(unsplitTokens: (o["tokenCount"] as? Int) ?? 0)],
            sourcePath: url.path
        )
    }

    /// 메시지 안의 `text` 값을 모두 모은다. 생각(reasoning) 블록은 뺀다.
    static func texts(in any: Any) -> [String] {
        if let dict = any as? [String: Any] {
            if let style = dict["style"] as? [String: Any], (style["type"] as? String) == "thinking" { return [] }
            if (dict["type"] as? String) == "text", let t = dict["text"] as? String { return [t] }
            return dict.filter { $0.key != "senderInfo" }.values.flatMap { texts(in: $0) }
        }
        if let array = any as? [Any] { return array.flatMap { texts(in: $0) } }
        return []
    }
}
