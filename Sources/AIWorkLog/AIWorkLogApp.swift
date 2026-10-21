import AppKit
import SwiftUI
import WorkLogCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // .app 묶음 없이 실행 파일만 띄워도 창이 앞에 나오게 한다.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // 설정에서 고른 화면 모드 (화면 확인용 --dark 는 이번에만 어둡게). --frame 은 창이 뜬 뒤 LaunchOptions 가 맞춘다.
        AppAppearance.saved.apply()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// 시작점은 main.swift (창 없이 쓰는 `cli` 모드를 먼저 가른다).
@MainActor
struct AIWorkLogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        // 메뉴 글자도 언어를 바꾸면 다시 만든다.
        let _ = model.language
        Window(L("AI 작업일지"), id: "main") {
            ContentView()
                .environment(model)
                .task {
                    LaunchOptions.apply(to: model)
                    model.refresh()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.appBecameActive()
                }
        }
        .defaultSize(width: 1240, height: 820)

        Settings {
            SettingsView()
                .environment(model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(L("기록")) {
                Button(L("새로 고침")) { model.refresh() }
                    .keyboardShortcut("r")
                Button(L("이 기간 보고서 만들기")) { model.makePeriodReport() }
                    .keyboardShortcut("e")
                Divider()
                Button(L("한눈에 보기")) { model.screen = .dashboard }.keyboardShortcut("1")
                Button(L("날짜별 기록")) { model.screen = .timeline }.keyboardShortcut("2")
                Button(L("모든 요청")) { model.screen = .prompts }.keyboardShortcut("3")
                Button(L("스킬·규칙")) { model.screen = .skills }.keyboardShortcut("4")
                Divider()
                Button(L("원본 기록 처음부터 다시 읽기")) { model.refresh(rereadSources: true) }
                Button(L("보관함 폴더 열기")) { if let url = model.storeURL { model.reveal(url.path) } }
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
        // --frame x,y,w,h: 창 자리와 크기. 터미널에서 띄우면 창이 실행 직후가 아니라 앱을 다시 열 때 생기기도 해서,
        // 앱이 뜰 때가 아니라 창 내용이 처음 나타날 때 맞춘다. 아래에서 화면(--screen)을 바꾸기 전에 맞춰야
        // 프로젝트 화면이 바뀐 너비로 처음 그려져 맨 위부터 보인다 (그린 뒤 넓히면 스크롤이 밀린다).
        if let f = value("--frame") {
            let n = f.split(separator: ",").compactMap { Double($0) }
            if n.count == 4 {
                let frame = NSRect(x: n[0], y: n[1], width: n[2], height: n[3])
                func place() -> Bool {
                    guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return false }
                    window.setFrame(frame, display: true)
                    return true
                }
                if !place() {
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        _ = place()
                    }
                }
            }
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
        if let t = value("--tools") { model.tools = Set(t.split(separator: ",").compactMap { AITool(rawValue: String($0)) }) }
        if args.contains("--report") {
            Task {
                while !model.hasLoaded || model.isLoading { try? await Task.sleep(for: .milliseconds(100)) }
                model.makePeriodReport()
            }
        }
        if args.contains("--tour") {
            Task {
                while !model.hasLoaded || model.isLoading { try? await Task.sleep(for: .milliseconds(100)) }
                try? await Task.sleep(for: .seconds(1.5))
                await tour(model)
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

extension LaunchOptions {
    static let isTour = ProcessInfo.processInfo.arguments.contains("--tour")
    /// README 첫머리의 20초 시연 영상(`--demo --tour`). 한눈에 보기 → 기간 바꾸기 → 프로젝트의 AI 요약 → 자세히 → 세션 → 스킬·규칙 → 검색.
    static func tour(_ model: AppModel) async {
        func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
        model.screen = .dashboard
        model.period = .month
        await wait(3)
        model.period = .week
        await wait(1.3)
        model.period = .month
        await wait(1.2)
        model.show(project: DemoData.root + "/todo-app")
        await wait(1.6)
        model.tourScrollToTabs += 1
        await wait(2.6)
        model.tourExpand = true
        await wait(2.8)
        model.tourExpand = false
        if let session = model.snapshot.sessions.first(where: { $0.sessionId == "demo-todo-app-2" }) { model.open(session) }
        await wait(3)
        model.path = []
        model.screen = .skills
        await wait(2.3)
        model.screen = .prompts
        // 시연 기록은 한국어판이 "위젯", 영어판이 "widget" 이라 화면 언어에 맞춰 찾는다.
        model.search = Loc.language == .ko ? "위젯" : "widget"
        await wait(2.5)
        model.search = ""
        model.screen = .dashboard
    }
}
