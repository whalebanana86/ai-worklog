import AppKit
import SwiftUI
import WorkLogCore

/// Checks public release metadata only. Installation stays an explicit user action.
@MainActor @Observable
final class AppUpdater {
    private(set) var isChecking = false
    private(set) var available: AppRelease?
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

    func check(interactive: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let url = URL(string: "https://api.github.com/repos/whalebanana86/ai-worklog/releases/latest")!
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("AIWorkLog/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let release = try JSONDecoder().decode(AppRelease.self, from: data)
            guard release.isStable, AppVersion(currentVersion) != nil else { throw URLError(.cannotParseResponse) }
            available = release.isNewer(than: currentVersion) ? release : nil
            if interactive { showResult() }
        } catch {
            if interactive {
                let alert = NSAlert()
                alert.messageText = L("업데이트를 확인하지 못했어요")
                alert.informativeText = L("인터넷 연결을 확인하고 다시 시도해 주세요.")
                alert.addButton(withTitle: L("닫기"))
                alert.runModal()
            }
        }
    }

    func showResult() {
        let alert = NSAlert()
        if let release = available {
            alert.messageText = L("새 버전 %@이 있어요", release.version)
            alert.informativeText = L("현재 버전은 %@이에요. 릴리스 페이지에서 DMG를 내려받아 앱을 응용 프로그램 폴더로 옮겨 주세요. 기존 기록은 유지돼요.", currentVersion)
            alert.addButton(withTitle: L("업데이트 다운로드"))
            alert.addButton(withTitle: L("나중에"))
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.htmlURL) }
        } else {
            alert.messageText = L("최신 버전을 사용 중이에요")
            alert.informativeText = L("현재 버전: %@", currentVersion)
            alert.addButton(withTitle: L("닫기"))
            alert.runModal()
        }
    }
}
