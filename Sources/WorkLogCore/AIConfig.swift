import Foundation

/// 프로젝트나 전역에 만들어 둔 AI 설정 파일 하나 (규칙, 스킬, 명령, 서브에이전트, 훅·권한, MCP).
public struct AIConfigItem: Hashable, Sendable, Identifiable {
    public enum Kind: String, CaseIterable, Sendable, Identifiable {
        case rule, skill, command, agent, settings, mcp

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .rule: return "규칙"
            case .skill: return "스킬"
            case .command: return "명령"
            case .agent: return "서브에이전트"
            case .settings: return "훅·권한"
            case .mcp: return "MCP 서버"
            }
        }

        public var symbol: String {
            switch self {
            case .rule: return "list.bullet.rectangle"
            case .skill: return "wand.and.stars"
            case .command: return "command"
            case .agent: return "person.2"
            case .settings: return "gearshape.2"
            case .mcp: return "puzzlepiece.extension"
            }
        }
    }

    public var kind: Kind
    /// 스킬·명령은 부를 때 쓰는 이름, 규칙은 파일 이름.
    public var name: String
    public var summary: String
    public var path: String
    /// 보여 줄 내용 (마크다운). 설정 파일은 비밀값이 있을 수 있어 요약만 담는다.
    public var body: String
    public var modified: Date
    /// 스킬 폴더 안 참고 파일 수.
    public var extraFiles: Int = 0
    /// 어디서 받아 온 스킬인지 (skills-lock.json, 플러그인 이름 등).
    public var origin: String?

    public var id: String { path }
}

/// 설정을 찾은 곳 하나 (프로젝트 폴더, 상위 폴더, 전역, 플러그인).
public struct AIConfigScope: Hashable, Sendable, Identifiable {
    public var title: String
    public var path: String
    public var items: [AIConfigItem]
    public var id: String { path + "#" + title }

    public init(title: String, path: String, items: [AIConfigItem]) {
        self.title = title
        self.path = path
        self.items = items
    }
}

public enum AIConfigScanner {
    static let maxBody = 60_000

    /// 한 폴더에 바로 들어 있는 AI 설정을 모은다 (하위 프로젝트까지 내려가지는 않는다).
    public static func scan(directory dir: String) -> [AIConfigItem] {
        guard !dir.isEmpty, !ProjectResolver.isPrivacyProtected(dir) else { return [] }
        var items: [AIConfigItem] = []
        let fm = FileManager.default
        func p(_ rel: String) -> String { (dir as NSString).appendingPathComponent(rel) }

        // 규칙: 도구들이 대화 시작 때 읽어 들이는 지침 파일
        for rel in ["CLAUDE.md", "CLAUDE.local.md", ".claude/CLAUDE.md", "AGENTS.md", "GEMINI.md",
                    ".cursorrules", ".windsurfrules", ".clinerules", ".github/copilot-instructions.md"] {
            if let item = markdownItem(kind: .rule, path: p(rel), name: rel) { items.append(item) }
        }
        for file in listFiles(p(".cursor/rules"), extensions: ["md", "mdc"]) {
            if let item = markdownItem(kind: .rule, path: file, name: ".cursor/rules/" + (file as NSString).lastPathComponent) { items.append(item) }
        }

        // 스킬: <skills>/<이름>/SKILL.md
        let lock = skillsLock(p("skills-lock.json"))
        for root in [".claude/skills", ".agents/skills", ".codex/skills"] {
            items += skills(in: p(root), lock: lock)
        }

        // 명령과 서브에이전트
        for file in listFiles(p(".claude/commands"), extensions: ["md"], recursive: true) {
            let rel = String(file.dropFirst(p(".claude/commands").count + 1))
            let name = "/" + (rel as NSString).deletingPathExtension.replacingOccurrences(of: "/", with: ":")
            if let item = markdownItem(kind: .command, path: file, name: name) { items.append(item) }
        }
        for file in listFiles(p(".claude/agents"), extensions: ["md"]) {
            if let item = markdownItem(kind: .agent, path: file, name: ((file as NSString).lastPathComponent as NSString).deletingPathExtension) {
                items.append(item)
            }
        }

        // 훅·권한, MCP — 비밀값이 섞일 수 있어 요약만
        for rel in [".claude/settings.json", ".claude/settings.local.json"] where fm.fileExists(atPath: p(rel)) {
            if let item = settingsItem(path: p(rel), name: rel) { items.append(item) }
        }
        if let item = mcpItem(path: p(".mcp.json"), name: ".mcp.json") { items.append(item) }
        return items
    }

    /// ~/.claude, ~/.codex 와 설치한 플러그인의 설정.
    public static func scanGlobal(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AIConfigScope] {
        var scopes: [AIConfigScope] = []
        let claude = home.appendingPathComponent(".claude").path
        var claudeItems: [AIConfigItem] = []
        if let item = markdownItem(kind: .rule, path: claude + "/CLAUDE.md", name: "~/.claude/CLAUDE.md") { claudeItems.append(item) }
        claudeItems += skills(in: claude + "/skills", lock: [:])
        for file in listFiles(claude + "/commands", extensions: ["md"], recursive: true) {
            let name = "/" + ((file as NSString).lastPathComponent as NSString).deletingPathExtension
            if let item = markdownItem(kind: .command, path: file, name: name) { claudeItems.append(item) }
        }
        for file in listFiles(claude + "/agents", extensions: ["md"]) {
            if let item = markdownItem(kind: .agent, path: file, name: ((file as NSString).lastPathComponent as NSString).deletingPathExtension) {
                claudeItems.append(item)
            }
        }
        if let item = settingsItem(path: claude + "/settings.json", name: "~/.claude/settings.json") { claudeItems.append(item) }
        if !claudeItems.isEmpty { scopes.append(AIConfigScope(title: "Claude Code 전역", path: claude, items: claudeItems)) }

        let codex = home.appendingPathComponent(".codex").path
        var codexItems: [AIConfigItem] = []
        if let item = markdownItem(kind: .rule, path: codex + "/AGENTS.md", name: "~/.codex/AGENTS.md") { codexItems.append(item) }
        codexItems += skills(in: codex + "/skills", lock: [:])
        if !codexItems.isEmpty { scopes.append(AIConfigScope(title: "Codex 전역", path: codex, items: codexItems)) }

        // Claude Code 플러그인
        let installed = claude + "/plugins/installed_plugins.json"
        if let data = FileManager.default.contents(atPath: installed),
           let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let plugins = o["plugins"] as? [String: [[String: Any]]] {
            for (id, installs) in plugins.sorted(by: { $0.key < $1.key }) {
                guard let path = installs.last?["installPath"] as? String else { continue }
                let name = id.split(separator: "@").first.map(String.init) ?? id
                let version = installs.last?["version"] as? String
                let items = skills(in: path + "/skills", lock: [:], origin: "플러그인 \(name)", prefix: name + ":")
                if !items.isEmpty {
                    scopes.append(AIConfigScope(title: "플러그인 \(name)" + (version.map { " \($0)" } ?? ""), path: path, items: items))
                }
            }
        }
        return scopes
    }

    // MARK: - 파일별

    private static func markdownItem(kind: AIConfigItem.Kind, path: String, name: String) -> AIConfigItem? {
        guard let text = read(path) else { return nil }
        let (fields, body) = Frontmatter.parse(text)
        return AIConfigItem(kind: kind, name: fields["name"].map { kind == .command ? "/" + $0 : $0 } ?? name,
                            summary: fields["description"] ?? Frontmatter.firstLine(body),
                            path: path, body: body, modified: modified(path))
    }

    private static func skills(in root: String, lock: [String: String], origin: String? = nil, prefix: String = "") -> [AIConfigItem] {
        var items: [AIConfigItem] = []
        for dir in subdirectories(root) {
            let skillFile = (dir as NSString).appendingPathComponent("SKILL.md")
            guard let text = read(skillFile) else { continue }
            let (fields, body) = Frontmatter.parse(text)
            let folder = (dir as NSString).lastPathComponent
            let name = fields["name"] ?? folder
            let count = (FileManager.default.enumerator(atPath: dir)?.allObjects.count ?? 1) - 1
            items.append(AIConfigItem(kind: .skill, name: prefix + name,
                                      summary: fields["description"] ?? Frontmatter.firstLine(body),
                                      path: skillFile, body: body, modified: modified(skillFile),
                                      extraFiles: max(0, count), origin: origin ?? lock[folder] ?? lock[name]))
        }
        return items
    }

    private static func settingsItem(path: String, name: String) -> AIConfigItem? {
        guard let data = FileManager.default.contents(atPath: path),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var lines: [String] = []
        if let hooks = o["hooks"] as? [String: Any], !hooks.isEmpty {
            let parts = hooks.keys.sorted().map { event -> String in
                let count = ((hooks[event] as? [[String: Any]]) ?? []).reduce(0) { $0 + ((($1["hooks"] as? [Any]) ?? []).count) }
                return "`\(event)` \(max(count, 1))개"
            }
            lines.append("- **훅**: " + parts.joined(separator: ", "))
        }
        if let perms = o["permissions"] as? [String: Any] {
            let allow = (perms["allow"] as? [Any])?.count ?? 0
            let deny = (perms["deny"] as? [Any])?.count ?? 0
            let ask = (perms["ask"] as? [Any])?.count ?? 0
            if allow + deny + ask > 0 { lines.append("- **권한 규칙**: 허용 \(allow) · 거부 \(deny) · 물어보기 \(ask)") }
            if let mode = perms["defaultMode"] as? String { lines.append("- **기본 권한 모드**: `\(mode)`") }
        }
        if let plugins = o["enabledPlugins"] as? [String: Any], !plugins.isEmpty {
            lines.append("- **켜 둔 플러그인**: " + plugins.keys.sorted().map { "`\($0)`" }.joined(separator: ", "))
        }
        if let env = o["env"] as? [String: Any], !env.isEmpty {
            lines.append("- **환경 변수** \(env.count)개 (값은 비밀일 수 있어 숨김)")
        }
        if o["statusLine"] != nil { lines.append("- **상태 줄** 사용") }
        if let model = o["model"] as? String { lines.append("- **모델**: `\(model)`") }
        guard !lines.isEmpty else { return nil }
        return AIConfigItem(kind: .settings, name: name, summary: "훅·권한·플러그인 설정 요약",
                            path: path, body: lines.joined(separator: "\n"), modified: modified(path))
    }

    private static func mcpItem(path: String, name: String) -> AIConfigItem? {
        guard let data = FileManager.default.contents(atPath: path),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let servers = o["mcpServers"] as? [String: [String: Any]], !servers.isEmpty else { return nil }
        let lines = servers.keys.sorted().map { key -> String in
            let s = servers[key] ?? [:]
            if let url = s["url"] as? String, let host = URL(string: url)?.host { return "- **\(key)**: 원격 (\(host))" }
            let command = ((s["command"] as? String).map { ($0 as NSString).lastPathComponent }) ?? "?"
            return "- **\(key)**: `\(command)` 실행"
        }
        return AIConfigItem(kind: .mcp, name: name, summary: "MCP 서버 \(servers.count)개: " + servers.keys.sorted().joined(separator: ", "),
                            path: path, body: lines.joined(separator: "\n") + "\n\n(접속 정보·키 같은 값은 숨김)", modified: modified(path))
    }

    /// `npx skills` 가 남기는 skills-lock.json: 스킬 이름 → 받아 온 곳.
    private static func skillsLock(_ path: String) -> [String: String] {
        guard let data = FileManager.default.contents(atPath: path),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let skills = o["skills"] as? [String: [String: Any]] else { return [:] }
        return skills.compactMapValues { $0["source"] as? String }
    }

    // MARK: - 파일 도우미

    private static func read(_ path: String) -> String? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue,
              let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return text.count > maxBody ? String(text.prefix(maxBody)) + "\n\n…(길어서 여기까지만)" : text
    }

    private static func modified(_ path: String) -> Date {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date) ?? .distantPast
    }

    private static func subdirectories(_ root: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().map { (root as NSString).appendingPathComponent($0) }
    }

    private static func listFiles(_ root: String, extensions: Set<String>, recursive: Bool = false) -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root) else { return [] }
        let names: [String] = recursive
            ? ((fm.enumerator(atPath: root)?.allObjects as? [String]) ?? [])
            : ((try? fm.contentsOfDirectory(atPath: root)) ?? [])
        return names.filter { extensions.contains(($0 as NSString).pathExtension) }.sorted().map { (root as NSString).appendingPathComponent($0) }
    }
}

/// `---` 로 감싼 머리말(name, description …)과 본문을 나눈다.
enum Frontmatter {
    static func parse(_ text: String) -> (fields: [String: String], body: String) {
        guard text.hasPrefix("---"),
              let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) else {
            return ([:], text)
        }
        var fields: [String: String] = [:]
        let header = text[text.index(text.startIndex, offsetBy: 3)..<end.lowerBound]
        for raw in header.split(separator: "\n") {
            guard let colon = raw.firstIndex(of: ":"), !raw.hasPrefix(" "), !raw.hasPrefix("\t") else { continue }
            let key = raw[..<colon].trimmingCharacters(in: .whitespaces)
            let value = raw[raw.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            if !key.isEmpty, !value.isEmpty { fields[key] = value }
        }
        let rest = text[end.upperBound...].drop { $0 != "\n" }
        return (fields, String(rest).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 본문 첫 줄 (제목 기호는 뗀다).
    static func firstLine(_ body: String) -> String {
        let line = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        return String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces).clipped(140)
    }
}
