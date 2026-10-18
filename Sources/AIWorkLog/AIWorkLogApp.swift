import AppKit
import SwiftUI
import WorkLogCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // .app 묶음 없이 실행 파일만 띄워도 창이 앞에 나오게 한다.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // 화면 확인용: --dark, --frame x,y,w,h
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if let i = args.firstIndex(of: "--frame"), i + 1 < args.count {
            let n = args[i + 1].split(separator: ",").compactMap { Double($0) }
            if n.count == 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NSApp.windows.first { $0.isVisible }?.setFrame(NSRect(x: n[0], y: n[1], width: n[2], height: n[3]), display: true)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// 시작점은 main.swift (창 없이 쓰는 `cli` 모드를 먼저 가른다).
struct AIWorkLogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("AI 작업일지", id: "main") {
            ContentView()
                .environment(model)
                .task {
                    LaunchOptions.apply(to: model)
                    model.refresh()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.refreshIfStale()
                }
        }
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("기록") {
                Button("새로 고침") { model.refresh() }
                    .keyboardShortcut("r")
                Button("이 기간 보고서 만들기") { model.makePeriodReport() }
                    .keyboardShortcut("e")
                Divider()
                Button("한눈에 보기") { model.screen = .dashboard }.keyboardShortcut("1")
                Button("날짜별 기록") { model.screen = .timeline }.keyboardShortcut("2")
                Button("모든 요청") { model.screen = .prompts }.keyboardShortcut("3")
                Button("스킬·규칙") { model.screen = .skills }.keyboardShortcut("4")
                Divider()
                Button("원본 기록 처음부터 다시 읽기") { model.refresh(rereadSources: true) }
                Button("보관함 폴더 열기") { if let url = model.storeURL { model.reveal(url.path) } }
            }
        }
    }
}

/// 화면 확인용 실행 옵션. 예) `--screen timeline --period week`, `--session <세션 id 앞부분>`
@MainActor
enum LaunchOptions {
    /// 화면 확인용: `--hover-day 2026-10-13` 이면 차트가 그날에 마우스를 올린 상태로 뜬다.
    static let hoverDay: Date? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--hover-day"), i + 1 < args.count else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: args[i + 1]).map { Calendar.current.startOfDay(for: $0) }
    }()

    static func apply(to model: AppModel) {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let p = value("--period"), let period = Period(rawValue: p) { model.period = period }
        switch value("--screen") {
        case "timeline": model.screen = .timeline
        case "prompts": model.screen = .prompts
        case "skills": model.screen = .skills
        case let s? where s.hasPrefix("project="): model.screen = .project(String(s.dropFirst("project=".count)))
        default: break
        }
        if let q = value("--search") { model.search = q }
        if args.contains("--report") {
            Task {
                while !model.hasLoaded || model.isLoading { try? await Task.sleep(for: .milliseconds(100)) }
                model.makePeriodReport()
            }
        }
        guard let sid = value("--session") else { return }
        // 기록을 다 읽은 다음에 연다.
        Task {
            while !model.hasLoaded { try? await Task.sleep(for: .milliseconds(100)) }
            // 로딩 화면이 걷히는 순간에 넘기면 SwiftUI 가 무시해서, 첫 화면이 그려진 뒤에 연다.
            try? await Task.sleep(for: .milliseconds(500))
            if let s = model.snapshot.sessions.first(where: { $0.sessionId.hasPrefix(sid) }) { model.open(s) }
        }
    }
}
