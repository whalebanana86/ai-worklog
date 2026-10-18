import Foundation

/// 세션이 실제로 어느 프로젝트를 다뤘는지 정한다.
///
/// `~/Workspaces/apps` 처럼 여러 프로젝트를 담은 폴더에서 AI 를 띄우고 그 안의 `food_rival` 만 고쳤다면,
/// 그 세션은 `apps` 가 아니라 `food_rival` 작업으로 묶는 게 맞다.
enum ProjectResolver {
    static let rootMarkers = [".git", "package.json", "pubspec.yaml", "Package.swift", "Cargo.toml", "go.mod",
                              "pyproject.toml", "requirements.txt", "build.gradle", "CLAUDE.md", "AGENTS.md", "README.md", "docs"]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var rootCache: [String: Bool] = [:]
    nonisolated(unsafe) private static var childCache: [String: [String]] = [:]

    /// 들여다보면 macOS 가 "문서 폴더에 접근하려고 합니다" 창을 띄우는 폴더.
    public static func isPrivacyProtected(_ path: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let protected = ["Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Library/Mobile Documents"]
        return protected.contains { path == "\(home)/\($0)" || path.hasPrefix("\(home)/\($0)/") }
    }

    static func resolve(cwd: String, touched: [String: Int], prompts: [PromptEntry] = []) -> String {
        guard !cwd.isEmpty, !isPrivacyProtected(cwd), !isProjectRoot(cwd) else { return cwd }
        let base = cwd.hasSuffix("/") ? cwd : cwd + "/"

        var counts: [String: Int] = [:]
        var total = 0
        for (path, n) in touched where path.hasPrefix(base) {
            let rest = path.dropFirst(base.count)
            let top = rest.firstIndex(of: "/").map { String(rest[..<$0]) } ?? ""
            counts[top, default: 0] += n
            total += n
        }
        if total > 0 {
            guard let best = counts.max(by: { $0.value < $1.value }), !best.key.isEmpty,
                  Double(best.value) / Double(total) >= 0.6 else { return cwd }
            let candidate = base + best.key
            if isProjectRoot(candidate) { return candidate }
            // 지금은 지워진 폴더라 표시 파일을 확인할 수 없으면, 고친 파일이 몰린 그 폴더로 본다.
            if !FileManager.default.fileExists(atPath: candidate) { return candidate }
            // ~/Workspaces 에서 띄워 apps/food_rival 을 고쳤다면, apps 는 프로젝트 묶음이니 한 단계 더 내려간다.
            if !childProjects(of: candidate).isEmpty { return resolve(cwd: candidate, touched: touched) }
            // 표시 파일 없는 프로젝트 안의 그냥 하위 폴더(reports/ 등)는 내려가지 않는다.
            return cwd
        }

        // 파일을 안 고친 세션은 프롬프트에 하위 프로젝트 이름이 나오는지 본다.
        let text = prompts.prefix(5).map(\.text).joined(separator: "\n").lowercased()
        guard !text.isEmpty else { return cwd }
        let mentioned = childProjects(of: cwd).filter { text.contains($0.lowercased()) }
        if mentioned.count == 1, let only = mentioned.first { return base + only }
        return cwd
    }

    static func isProjectRoot(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let cached = rootCache[path] { return cached }
        let fm = FileManager.default
        let result = rootMarkers.contains { fm.fileExists(atPath: (path as NSString).appendingPathComponent($0)) }
        rootCache[path] = result
        return result
    }

    static func childProjects(of path: String) -> [String] {
        lock.lock()
        if let cached = childCache[path] { lock.unlock(); return cached }
        lock.unlock()
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
            .filter { !$0.hasPrefix(".") && $0.count >= 3 }
            .filter { isProjectRoot((path as NSString).appendingPathComponent($0)) }
        lock.lock(); childCache[path] = names; lock.unlock()
        return names
    }
}
