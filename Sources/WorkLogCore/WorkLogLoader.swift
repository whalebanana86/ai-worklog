import Foundation

/// 모든 AI 도구의 기록을 읽어 보관함(WorkLogStore)에 쌓고, 하나로 모아 돌려준다.
///
/// Claude Code 기록은 수 GB 까지 커지므로, 파일마다 읽은 위치와 중간 결과를 보관함에 두고 늘어난 부분만 읽는다.
public final class WorkLogLoader: @unchecked Sendable {
    public let claude: ClaudeCodeSource
    public let codex: CodexSource
    public let lmStudio: LMStudioSource
    public let store: WorkLogStore?
    public let storeError: String?

    private var archive: [String: WorkSession] = [:]
    private var archivedNotes: [String: [MemoryNote]] = [:]
    private var sources: [String: WorkLogStore.SourceState] = [:]
    private var archiveLoaded = false
    private let lock = NSLock()

    /// `storeURL` 이 nil 이면 보관함 없이 매번 원본만 읽는다 (검증용).
    public init(claude: ClaudeCodeSource = .init(), codex: CodexSource = .init(), lmStudio: LMStudioSource = .init(),
                storeURL: URL? = WorkLogStore.defaultURL) {
        self.claude = claude
        self.codex = codex
        self.lmStudio = lmStudio
        guard let storeURL else {
            store = nil
            storeError = nil
            return
        }
        do {
            store = try WorkLogStore(url: storeURL)
            storeError = nil
        } catch {
            store = nil
            storeError = "보관함을 열지 못했습니다: \(error)"
        }
        // 보관함 전에 쓰던 캐시 파일은 이제 필요 없다.
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent().appendingPathComponent("cache.plist"))
    }

    /// 보관함에 있는 것만 바로 돌려준다. 앱을 켜자마자 보여 주기용. 보관함이 비었으면 nil.
    public func loadArchived() -> WorkLogSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        var warnings: [String] = []
        loadArchiveIfNeeded(warnings: &warnings)
        guard !archive.isEmpty else { return nil }
        return snapshot(notes: archivedNotes, warnings: warnings, synced: false)
    }

    /// 원본을 확인해 보관함을 최신으로 만들고 전체를 돌려준다.
    /// `progress` 는 (읽은 파일 수, 전체 파일 수) 로 불린다.
    public func load(progress: (@Sendable (Int, Int) -> Void)? = nil) -> WorkLogSnapshot {
        lock.lock()
        defer { lock.unlock() }

        var warnings: [String] = []
        if let storeError { warnings.append(storeError) }
        loadArchiveIfNeeded(warnings: &warnings)

        var changed: [String: WorkSession] = [:]
        func absorb(_ s: WorkSession) {
            let next = archive[s.id].map { s.merged(withArchived: $0) } ?? s
            if archive[s.id] != next {
                archive[s.id] = next
                changed[s.id] = next
            }
        }

        // 1. Claude Code 대화 원본
        let (claudeSessions, changedSources, seenPaths) = loadClaude(progress: progress, warnings: &warnings)
        claudeSessions.forEach(absorb)

        // 2. 원본이 지워진 세션은 보관본으로 표시만 하고 지우지 않는다.
        for (key, s) in archive where s.tool == .claudeCode && s.hasTranscript && !s.sourceMissing {
            guard let path = s.sourcePath, !seenPaths.contains(path), !FileManager.default.fileExists(atPath: path) else { continue }
            archive[key]?.sourceMissing = true
            changed[key] = archive[key]
        }

        // 3. 대화 원본 없이 입력 기록만 남은 Claude Code 세션 (답변까지 있는 보관본이 있으면 그쪽이 우선)
        let withTranscript = Set(archive.values.filter { $0.tool == .claudeCode && $0.hasTranscript }.map(\.sessionId))
        claude.historySessions(excluding: withTranscript).forEach(absorb)

        // 4. 다른 도구
        codex.load(warnings: &warnings).forEach(absorb)
        lmStudio.load().forEach(absorb)

        // 5. AI 메모: 지금 있는 것 + 지워졌지만 보관된 것
        var paths = Set(archive.values.map(\.cwd))
        paths.formUnion(archive.values.map(\.projectPath))
        let currentNotes = claude.memoryNotes(knownPaths: paths)
        var notes = archivedNotes
        for (root, list) in currentNotes {
            let fresh = Set(list.map(\.path))
            notes[root] = list + (notes[root] ?? []).filter { !fresh.contains($0.path) }
        }
        archivedNotes = notes

        if let store {
            do {
                try store.save(sessions: Array(changed.values), sources: changedSources, notesByRoot: currentNotes)
                if !changed.isEmpty || !changedSources.isEmpty { store.compact() }
            } catch {
                warnings.append("보관함에 저장하지 못했습니다: \(error)")
            }
        }
        return snapshot(notes: notes, warnings: warnings, synced: true)
    }

    private func snapshot(notes: [String: [MemoryNote]], warnings: [String], synced: Bool) -> WorkLogSnapshot {
        var snap = WorkLogSnapshot(sessions: archive.values.sorted { $0.end > $1.end }, notesByRoot: notes, loadedAt: Date(),
                                   warnings: warnings, store: store?.stats(), isSynced: synced)
        if synced {
            snap.configs = scanConfigs()
            snap.globalConfigs = AIConfigScanner.scanGlobal()
        }
        return snap
    }

    /// 세션이 있었던 폴더와 그 상위 폴더(홈 폴더 바로 아래까지)의 AI 설정.
    private func scanConfigs() -> [String: [AIConfigItem]] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = Set<String>()
        for s in archive.values {
            for start in [s.projectPath, s.cwd] where start.hasPrefix(home + "/") {
                var dir = start
                while dir.hasPrefix(home + "/"), dirs.insert(dir).inserted {
                    dir = (dir as NSString).deletingLastPathComponent
                }
            }
        }
        var result: [String: [AIConfigItem]] = [:]
        for dir in dirs {
            let items = AIConfigScanner.scan(directory: dir)
            if !items.isEmpty { result[dir] = items }
        }
        return result
    }

    private func loadArchiveIfNeeded(warnings: inout [String]) {
        guard !archiveLoaded else { return }
        archiveLoaded = true
        guard let store else { return }
        do {
            archive = try store.loadSessions()
            archivedNotes = try store.loadNotes()
            sources = try store.loadSources()
        } catch {
            warnings.append("보관함을 읽지 못했습니다: \(error)")
        }
    }

    /// 늘어난 원본만 읽는다. 바뀐 파일의 세션, 바뀐 읽기 위치, 이번에 본 파일 경로를 돌려준다.
    private func loadClaude(progress: (@Sendable (Int, Int) -> Void)?, warnings: inout [String])
        -> ([WorkSession], [String: WorkLogStore.SourceState], Set<String>) {
        let files = claude.transcriptFiles()
        let previous = sources
        let archived = archive

        // 큰 파일부터 나눠 읽어야 마지막에 큰 파일 하나만 남아 기다리는 일이 줄어든다.
        let ordered = files
            .map { ($0, (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            .sorted { $0.1 > $1.1 }

        let resultLock = NSLock()
        var updated: [String: WorkLogStore.SourceState] = [:]
        var failures: [String] = []
        var done = 0
        let total = ordered.count

        DispatchQueue.concurrentPerform(iterations: ordered.count) { i in
            let (url, size) = ordered[i]
            let path = url.path
            defer {
                resultLock.lock()
                done += 1
                let finished = done
                resultLock.unlock()
                progress?(finished, total)
            }
            var state: WorkLogStore.SourceState
            let sessionKey = "\(AITool.claudeCode.rawValue):\(url.deletingPathExtension().lastPathComponent)"
            if let old = previous[path], old.size <= size, old.offset <= size,
               old.accumulator.version == ClaudeAccumulator.parserVersion,
               old.size == size || archived[sessionKey] != nil {
                if old.size == size { return }
                // 읽기 상태에는 요청이 빠져 있으니 보관함의 요청을 채워서 이어 읽는다.
                state = old
                state.accumulator = old.accumulator.resumed(withArchived: archived[sessionKey]) ?? old.accumulator
            } else {
                // 처음 보거나, 파일이 줄었거나(다시 써졌거나), 해석 규칙이 바뀌었으면 처음부터 읽는다.
                state = .init(size: 0, offset: 0, accumulator: ClaudeAccumulator(sessionId: url.deletingPathExtension().lastPathComponent))
            }
            do {
                var acc = state.accumulator
                let offset = try LineScanner.scan(path: path, from: state.offset) { line in
                    // 도구 실행 결과 줄이 전체 용량의 2/3 를 차지하는데 쓸 데가 없어서, 해석하지 않고 넘긴다.
                    if LineScanner.contains(line, "\"toolUseResult\"") { return }
                    // API 요청 사본(도구 결과를 통째로 담은 큰 줄)도 쓸 데가 없다.
                    if LineScanner.hasPrefix(line, "{\"type\":\"api-request-blob\"") { return }
                    guard let o = LineScanner.jsonObject(line) else { return }
                    acc.ingest(o)
                }
                resultLock.lock()
                updated[path] = .init(size: size, offset: offset, accumulator: acc)
                resultLock.unlock()
            } catch {
                resultLock.lock()
                failures.append(url.lastPathComponent)
                resultLock.unlock()
            }
        }

        if !failures.isEmpty {
            warnings.append("Claude Code 기록 \(failures.count)개를 읽지 못했습니다: \(failures.prefix(3).joined(separator: ", "))")
        }
        // 메모리에 남기는 읽기 상태에서도 요청 목록은 뺀다 (보관함 세션에 같은 내용이 있다).
        for (path, state) in updated {
            var light = state
            light.accumulator.prompts = []
            sources[path] = light
        }

        let sessions = updated.compactMap { path, state in
            state.accumulator.makeSession(sourcePath: path, subagents: claude.subagentCount(for: URL(fileURLWithPath: path)))
        }
        return (sessions, updated, Set(files.map(\.path)))
    }

    /// 원본을 처음부터 다시 읽게 한다. 보관된 세션은 그대로 남는다.
    public func rereadSources() {
        lock.lock()
        defer { lock.unlock() }
        sources = [:]
        try? store?.eraseReadPositions()
    }
}
