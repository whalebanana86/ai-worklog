import Foundation

/// 기록을 남기는 로컬 AI 도구.
public enum AITool: String, Codable, CaseIterable, Sendable, Identifiable {
    case claudeCode
    case codex
    case lmStudio

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .lmStudio: return "LM Studio"
        }
    }

    /// 터미널에서 이 세션을 이어서 여는 명령. 지원하지 않는 도구는 nil.
    public func resumeCommand(sessionId: String, cwd: String) -> String? {
        let dir = cwd.replacingOccurrences(of: "'", with: "'\\''")
        switch self {
        case .claudeCode: return "cd '\(dir)' && claude --resume \(sessionId)"
        case .codex: return "cd '\(dir)' && codex resume \(sessionId)"
        case .lmStudio: return nil
        }
    }
}

/// 사람이 AI 에게 보낸 요청 한 건과, 그 요청에 대한 AI 의 마지막 답변.
public struct PromptEntry: Codable, Hashable, Sendable {
    public var date: Date
    public var text: String
    /// `/login` 같은 슬래시 명령.
    public var isCommand: Bool
    /// 사람이 직접 친 게 아니라 스크립트·예약 작업이 보낸 요청.
    public var isAutomated: Bool
    /// 이 요청 다음, 다음 요청 전까지 AI 가 마지막으로 한 말.
    public var reply: String?
    /// 이 요청을 처리하며 AI 가 고친 파일 (고친 순서).
    public var files: [String] = []
    /// 이 요청에서 늘고 준 줄 수 (편집 내용으로 어림한 값).
    public var linesAdded = 0
    public var linesRemoved = 0

    public init(date: Date, text: String, isCommand: Bool = false, isAutomated: Bool = false, reply: String? = nil) {
        self.date = date
        self.text = text
        self.isCommand = isCommand
        self.isAutomated = isAutomated
        self.reply = reply
    }

    mutating func noteEdit(_ path: String, added: Int, removed: Int) {
        if !files.contains(path) { files.append(path) }
        linesAdded += added
        linesRemoved += removed
    }
}

public struct ModelUsage: Codable, Hashable, Sendable {
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheReadTokens: Int = 0
    public var cacheWriteTokens: Int = 0
    /// 입력·출력 구분 없이 합계만 남는 도구(Codex)의 토큰 수.
    public var unsplitTokens: Int = 0
    public var costUSD: Double?

    public init(inputTokens: Int = 0, outputTokens: Int = 0, cacheReadTokens: Int = 0, cacheWriteTokens: Int = 0,
                unsplitTokens: Int = 0, costUSD: Double? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.unsplitTokens = unsplitTokens
        self.costUSD = costUSD
    }

    public var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens + unsplitTokens }
}

/// AI 가 고치거나 만든 파일.
public struct FileTouch: Codable, Hashable, Sendable, Identifiable {
    public var path: String
    public var edits: Int
    public var id: String { path }

    public init(path: String, edits: Int) {
        self.path = path
        self.edits = edits
    }
}

/// AI 와 한 번 앉아서 한 작업(세션) 하나.
public struct WorkSession: Codable, Hashable, Sendable, Identifiable {
    public var tool: AITool
    public var sessionId: String
    public var title: String
    /// AI 를 띄운 폴더.
    public var cwd: String
    /// 실제로 손댄 프로젝트 폴더. 상위 폴더에서 띄워 하위 프로젝트만 고쳤다면 하위 폴더가 된다.
    public var projectPath: String
    public var gitBranch: String?
    public var start: Date
    public var end: Date
    /// 10분 넘게 쉰 구간을 뺀, 실제로 주고받은 시간.
    public var activeSeconds: Double
    public var prompts: [PromptEntry]
    public var files: [FileTouch]
    public var toolUses: [String: Int]
    public var models: [String: ModelUsage]
    public var costUSD: Double?
    public var linesAdded: Int?
    public var linesRemoved: Int?
    public var subagents: Int
    /// 원본 기록 파일. 기록이 지워지고 프롬프트만 남았으면 nil.
    public var sourcePath: String?
    /// false 면 대화 원본은 지워지고 프롬프트 기록만 남은 세션.
    public var hasTranscript: Bool
    /// 원본 기록 파일은 지워졌지만 이 앱 보관함에 내용이 남아 있는 세션.
    public var sourceMissing = false
    /// 이 세션에서 쓴 스킬·사용자 명령과 횟수 (AI 가 부른 것 + 내가 /이름 으로 부른 것).
    public var skillsUsed: [String: Int] = [:]

    public var id: String { "\(tool.rawValue):\(sessionId)" }

    public var userPrompts: [PromptEntry] { prompts.filter { !$0.isCommand } }
    /// 사람이 아니라 스크립트·예약 작업이 돌린 세션.
    public var isAutomated: Bool {
        let real = userPrompts
        return !real.isEmpty && real.allSatisfy(\.isAutomated)
    }
    public var totalTokens: Int { models.values.reduce(0) { $0 + $1.totalTokens } }
    public var finalAnswer: String? { prompts.last(where: { $0.reply != nil })?.reply }
    public var projectName: String { WorkSession.displayName(forPath: projectPath) }

    public static func displayName(forPath path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    public init(tool: AITool, sessionId: String, title: String, cwd: String, projectPath: String, gitBranch: String? = nil,
                start: Date, end: Date, activeSeconds: Double, prompts: [PromptEntry], files: [FileTouch] = [],
                toolUses: [String: Int] = [:], models: [String: ModelUsage] = [:], costUSD: Double? = nil,
                linesAdded: Int? = nil, linesRemoved: Int? = nil, subagents: Int = 0, sourcePath: String? = nil,
                hasTranscript: Bool = true) {
        self.tool = tool
        self.sessionId = sessionId
        self.title = title
        self.cwd = cwd
        self.projectPath = projectPath
        self.gitBranch = gitBranch
        self.start = start
        self.end = end
        self.activeSeconds = activeSeconds
        self.prompts = prompts
        self.files = files
        self.toolUses = toolUses
        self.models = models
        self.costUSD = costUSD
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.subagents = subagents
        self.sourcePath = sourcePath
        self.hasTranscript = hasTranscript
    }
}

/// 프로젝트 폴더에 AI 가 남겨 둔 메모(Claude Code 의 memory/*.md).
public struct MemoryNote: Codable, Hashable, Sendable, Identifiable {
    public var path: String
    public var name: String
    public var summary: String
    public var kind: String?
    public var body: String
    public var modified: Date
    public var id: String { path }
}

public struct ProjectSummary: Hashable, Sendable, Identifiable {
    public var path: String
    public var sessions: [WorkSession]
    public var notes: [MemoryNote]

    public var id: String { path }
    public var name: String { WorkSession.displayName(forPath: path) }
    public var lastActive: Date { sessions.map(\.end).max() ?? .distantPast }
    public var firstActive: Date { sessions.map(\.start).min() ?? .distantPast }
    public var activeSeconds: Double { sessions.reduce(0) { $0 + $1.activeSeconds } }
    public var promptCount: Int { sessions.reduce(0) { $0 + $1.userPrompts.count } }
    public var tools: Set<AITool> { Set(sessions.map(\.tool)) }
    public var skillsUsed: [String: Int] {
        sessions.reduce(into: [:]) { acc, s in for (k, v) in s.skillsUsed { acc[k, default: 0] += v } }
    }
}

/// 한 번 읽어 들인 전체 기록.
public struct WorkLogSnapshot: Sendable {
    public var sessions: [WorkSession]
    public var notesByRoot: [String: [MemoryNote]]
    public var loadedAt: Date
    public var warnings: [String]
    public var store: WorkLogStore.Stats?
    /// 폴더별 AI 설정(규칙·스킬·명령…). 프로젝트 폴더와 그 상위 폴더들.
    public var configs: [String: [AIConfigItem]] = [:]
    /// ~/.claude, ~/.codex, 플러그인.
    public var globalConfigs: [AIConfigScope] = []
    /// 원본까지 확인해서 최신인지 (false 면 보관함 내용만 먼저 띄운 상태).
    public var isSynced: Bool

    public init(sessions: [WorkSession], notesByRoot: [String: [MemoryNote]], loadedAt: Date = Date(), warnings: [String] = [],
                store: WorkLogStore.Stats? = nil, isSynced: Bool = true) {
        self.sessions = sessions
        self.notesByRoot = notesByRoot
        self.loadedAt = loadedAt
        self.warnings = warnings
        self.store = store
        self.isSynced = isSynced
    }

    public static let empty = WorkLogSnapshot(sessions: [], notesByRoot: [:], loadedAt: .distantPast)
}
