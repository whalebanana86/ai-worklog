import AppKit
import SwiftUI
import WorkLogCore

@MainActor @Observable
final class AppUpdater {
    private(set) var isChecking = false
    private(set) var isInstalling = false
    private(set) var available: AppRelease?
    private(set) var progress: Double?
    private(set) var status: String?
    private(set) var error: String?
    var isPresented = false
    @ObservationIgnored private weak var updateWindow: NSWindow?

    func attachUpdateWindow(_ window: NSWindow?) { updateWindow = window }
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

    var canAutomaticallyInstall: Bool { available?.updateAsset != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func check(interactive: Bool) async {
        guard !isChecking, !isInstalling else { return }
        if interactive { isPresented = true; error = nil }
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
        } catch {
            if interactive { self.error = L("업데이트를 확인하지 못했어요") + "\n" + error.localizedDescription }
        }
    }

    func showResult() { isPresented = true }

    func readInstallationResult() {
        let url = UpdateInstallation.resultURL
        guard let data = try? Data(contentsOf: url), let result = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        try? FileManager.default.removeItem(at: url)
        if let message = result["error"] { error = message; isPresented = true }
    }

    func install(canQuit: @MainActor () -> Bool) async {
        guard !isInstalling, !isChecking, let release = available else { return }
        guard canQuit() else { error = L("기록 읽기, AI 요약과 보고서 편집을 마친 뒤 업데이트해 주세요."); return }
        guard let asset = release.updateAsset else { error = AppUpdateError.invalidAsset.localizedDescription; return }
        isInstalling = true
        error = nil
        progress = nil
        status = L("업데이트를 다운로드하는 중…")
        let fm = FileManager.default
        let workspace = fm.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("AIWorkLogUpdate-" + UUID().uuidString, isDirectory: true)
        var prepared: UpdatePlan?
        do {
            try fm.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            var request = URLRequest(url: asset.browserDownloadURL, timeoutInterval: 300)
            request.setValue("AIWorkLog/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let updater = self
            let delegate = UpdateDownloadProgress { written, total in
                Task { @MainActor in updater.progress = total > 0 ? min(1, Double(written) / Double(total)) : nil }
            }
            let (temporary, response) = try await URLSession.shared.download(for: request, delegate: delegate)
            defer { try? fm.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let zip = workspace.appendingPathComponent("update.zip")
            try fm.moveItem(at: temporary, to: zip)
            status = L("업데이트 파일과 앱을 검증하는 중…")
            progress = nil
            let target = Bundle.main.bundleURL
            let plan = try await Task.detached(priority: .userInitiated) {
                try UpdateArchive.verify(zip, digest: asset.digest, size: asset.size)
                let app = try UpdateArchive.extract(zip, into: workspace.appendingPathComponent("unpacked", isDirectory: true))
                return try UpdateInstallation.prepare(app: app, target: target, workspace: workspace, version: release.version)
            }.value
            prepared = plan
            // A summary or report may have started while the file was downloading.
            guard canQuit() else { throw UpdateBusyError() }
            let planURL = workspace.appendingPathComponent("install.json")
            try JSONEncoder().encode(plan).write(to: planURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: planURL.path)
            let helper = workspace.appendingPathComponent("installer")
            guard let executable = Bundle.main.executableURL else { throw AppUpdateError.invalidApp }
            try fm.copyItem(at: executable, to: helper)
            let process = Process()
            process.executableURL = helper
            process.arguments = ["--install-update", planURL.path]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            // Remove an earlier attempt's result before starting this helper.
            try? fm.removeItem(at: UpdateInstallation.resultURL)
            try process.run()
            status = L("앱을 교체하고 다시 시작하는 중…")
            // AppKit refuses termination while a modal sheet prohibits it, even
            // before consulting the app delegate. Only release our update sheet.
            updateWindow?.preventsApplicationTerminationWhenModal = false
            isPresented = false
            if let window = updateWindow, let parent = window.sheetParent {
                parent.endSheet(window)
            }
            await UpdateShutdown.request(
                terminate: { NSApp.terminate(nil) },
                stillRunning: {
                    // If control returns and the app remains alive, the helper
                    // can only be waiting for this PID. Cancel it before cleanup.
                    await UpdateShutdown.cancelWaitingHelper(process)
                    self.resetAfterFailedHandoff(plan)
                }
            )
        } catch {
            if let prepared { try? fm.removeItem(at: prepared.candidate) }
            try? fm.removeItem(at: workspace)
            self.error = error.localizedDescription
            status = nil
            progress = nil
            isInstalling = false
        }
    }

    private func resetAfterFailedHandoff(_ plan: UpdatePlan) {
        try? UpdateInstallation.cleanupTemporaryFiles(plan)
        isInstalling = false
        status = nil
        progress = nil
        error = L("앱을 자동으로 종료하지 못해 업데이트를 취소했어요. 기존 앱은 그대로예요. 다시 시도해 주세요.")
        readInstallationResult()
        isPresented = true
    }

}

private struct UpdateBusyError: LocalizedError {
    var errorDescription: String? { L("기록 읽기, AI 요약과 보고서 편집을 마친 뒤 업데이트해 주세요.") }
}

private final class UpdateDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let changed: @Sendable (Int64, Int64) -> Void
    init(changed: @escaping @Sendable (Int64, Int64) -> Void) { self.changed = changed }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > 100 * 1024 * 1024 { downloadTask.cancel() }
        changed(totalBytesWritten, totalBytesExpectedToWrite)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
}

@MainActor
struct AppUpdateSheet: View {
    @Bindable var updater: AppUpdater
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("업데이트 확인…")).font(.title2.bold())
            if updater.isChecking {
                ProgressView(L("업데이트 확인 중…"))
            } else if let status = updater.status {
                Text(status)
                if let progress = updater.progress {
                    ProgressView(value: progress)
                    Text("\(Int(progress * 100))%").monospacedDigit().foregroundStyle(.secondary)
                } else { ProgressView().controlSize(.small) }
            } else if let release = updater.available {
                Text(L("새 버전 %@이 있어요", release.version)).font(.headline)
                Text(L("현재 버전: %@", updater.currentVersion)).foregroundStyle(.secondary)
                Text(updater.canAutomaticallyInstall
                     ? L("업데이트 파일을 다운로드하고 검증한 뒤 앱을 교체하고 다시 시작해요. 기존 기록과 설정은 유지돼요.")
                     : L("이 버전은 다운로드 페이지에서 DMG를 받아 직접 설치해 주세요."))
            } else if updater.error == nil {
                Text(L("최신 버전을 사용 중이에요"))
                Text(L("현재 버전: %@", updater.currentVersion)).foregroundStyle(.secondary)
            }
            if let error = updater.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Button(L("닫기")) { updater.isPresented = false }.disabled(updater.isInstalling)
                Spacer()
                if !updater.isChecking && !updater.isInstalling {
                    if let release = updater.available {
                        if updater.canAutomaticallyInstall {
                            Button(L("설치하고 다시 시작")) { Task { await updater.install { model.canInstallAppUpdate } } }
                                .buttonStyle(.borderedProminent)
                        }
                        if !updater.canAutomaticallyInstall || updater.error != nil {
                            Button(L("다운로드 페이지 열기")) { NSWorkspace.shared.open(release.htmlURL) }
                        }
                    } else if updater.error != nil {
                        Button(L("다시 확인")) { Task { await updater.check(interactive: true) } }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 480)
        .interactiveDismissDisabled(updater.isInstalling)
        .background(UpdateSheetWindowReader { updater.attachUpdateWindow($0) })
    }
}

/// Access the specific sheet window; never change other windows or report dialogs.
private struct UpdateSheetWindowReader: NSViewRepresentable {
    var changed: (NSWindow?) -> Void
    func makeNSView(context: Context) -> WindowReader {
        let view = WindowReader()
        view.changed = changed
        return view
    }
    func updateNSView(_ view: WindowReader, context: Context) { view.changed = changed }

    final class WindowReader: NSView {
        var changed: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            changed?(window)
        }
    }
}
