import Foundation

/// README 스크린샷·시연용으로 지어낸 기록 (`--demo`). 실제 기록과 보관함은 읽지도 쓰지도 않는다.
/// 날짜는 실행한 날을 기준으로 잡아서, 언제 띄워도 "오늘"부터 4주 동안 일한 모습이 나온다.
public enum DemoData {
    /// 지어낸 프로젝트들이 있는 척하는 폴더 (`~/Projects/…`).
    public static var root: String { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects").path }

    /// 요약을 맡긴 척하는 도구. 시연 모드에서는 실제로 부르지 않는다.
    public static let engine = SummaryEngine(kind: .claudeCode, location: "/usr/local/bin/claude", searchPath: "")

    struct Ask {
        var text: String
        var reply: String
        var files: [String] = []
        var added = 0
        var removed = 0
    }

    struct Work {
        var project: String
        var tool: AITool
        var title: String
        var daysAgo: Int
        /// 지난 날은 시작 시각, 오늘은 무시하고 "조금 전"에 끝난 것으로 잡는다.
        var hour: Int
        /// 요청 사이 간격(분). 10분이 넘으면 쉰 것으로 쳐서 작업 시간에 넣지 않으니 그 안으로 둔다.
        var gaps: [Int]
        var asks: [Ask]
        var model: String
        var tokens: Int
        var cost: Double?
        var skills: [String: Int] = [:]
        /// 그날의 AI 요약 (한 줄 + 핵심 결과).
        var headline: String
        var points: [String]
    }

    static let works: [Work] = [
        Work(project: "todo-app", tool: .claudeCode, title: "마감 알림과 아이콘 배지", daysAgo: 0, hour: 10, gaps: [0, 9, 10, 10], asks: [
            Ask(text: "마감 시간 30분 전에 알림이 오게 해 줘",
                reply: "할 일을 저장할 때 마감 30분 전으로 로컬 알림을 예약하는 NotificationScheduler 를 만들었어요. 마감을 바꾸면 예약도 다시 잡아요.",
                files: ["Sources/Notifications/NotificationScheduler.swift", "Sources/Models/TodoStore.swift"], added: 86, removed: 4),
            Ask(text: "알림 권한을 거절하면 설정으로 가는 안내를 띄워 줘",
                reply: "권한이 꺼져 있으면 목록 위에 안내 띠를 보여 주고, 누르면 시스템 설정의 알림 화면을 열게 했어요.",
                files: ["Sources/Views/PermissionBanner.swift"], added: 42),
            Ask(text: "알림 테스트도 추가해 줘",
                reply: "알림 시각 계산, 마감이 지난 할 일 건너뛰기, 마감 변경 시 다시 예약을 확인하는 테스트 6개를 추가했고 모두 통과했어요.",
                files: ["Tests/NotificationSchedulerTests.swift"], added: 71),
            Ask(text: "앱 아이콘 배지에 오늘 남은 할 일 수를 보여 줘",
                reply: "오늘 마감인 할 일 수를 앱 아이콘 배지로 보여 주게 했어요. 다 끝내면 배지가 사라져요.",
                files: ["Sources/App/TodoApp.swift", "Sources/Models/TodoStore.swift"], added: 23, removed: 2),
        ], model: "claude-opus-5-5", tokens: 1_840_000, cost: 3.12, skills: ["write-tests": 1],
             headline: "마감 알림과 권한 안내 추가",
             points: ["마감 30분 전 로컬 알림 예약, 마감을 바꾸면 다시 예약함", "알림 권한이 꺼져 있으면 설정으로 가는 안내 띠 추가",
                      "알림 계산 테스트 6개 추가, 모두 통과"]),
        Work(project: "my-blog", tool: .codex, title: "글 검색 만들기", daysAgo: 1, hour: 20, gaps: [0, 10, 8], asks: [
            Ask(text: "블로그 글 제목이랑 본문으로 검색되게 해 줘",
                reply: "빌드할 때 글 목록으로 검색 색인(search-index.json)을 만들고, 위쪽 검색 칸에서 제목·본문을 바로 찾게 했어요.",
                files: ["scripts/build-search-index.ts", "components/SearchBox.tsx"], added: 132, removed: 6),
            Ask(text: "검색 결과에 찾은 글자를 형광펜으로 칠해 줘",
                reply: "검색어와 맞는 부분을 <mark> 로 감싸고, 본문은 찾은 글자 앞뒤 40자만 잘라 보여 줘요.",
                files: ["components/SearchResult.tsx"], added: 48, removed: 9),
            Ask(text: "한글 초성으로도 찾을 수 있어?",
                reply: "제목은 초성 색인을 따로 만들어 'ㅂㄹㄱ' 처럼 쳐도 찾게 했어요. 본문까지 하면 색인이 3배 커져서 제목만 했어요.",
                files: ["scripts/build-search-index.ts"], added: 27, removed: 3),
        ], model: "gpt-5.5-codex", tokens: 920_000,
             headline: "제목·본문 검색과 초성 검색 추가",
             points: ["빌드 때 검색 색인을 만들어 위쪽 검색 칸에서 바로 찾게 함", "찾은 글자 형광펜 표시, 본문은 앞뒤 40자만 보여 줌",
                      "제목은 초성으로도 찾게 함 (본문은 색인이 커져서 뺌)"]),
        Work(project: "todo-app", tool: .claudeCode, title: "다크 모드와 홈 화면 위젯", daysAgo: 2, hour: 14, gaps: [0, 10, 10], asks: [
            Ask(text: "다크 모드에서 글자가 잘 안 보여. 색을 다시 잡아 줘",
                reply: "색을 의미 색(배경·글자·강조)으로 바꿔서 밝은 화면과 어두운 화면 모두 글자 대비가 4.5:1 이상이 되게 했어요.",
                files: ["Resources/Colors.xcassets", "Sources/Views/TodoRow.swift"], added: 58, removed: 31),
            Ask(text: "홈 화면 위젯 만들어 줘. 오늘 할 일 3개를 보여 주게",
                reply: "오늘 할 일 3개와 남은 개수를 보여 주는 위젯을 추가했어요. 앱과 위젯이 같은 저장소를 쓰도록 App Group 으로 묶었어요.",
                files: ["Widget/TodayWidget.swift", "Sources/Models/SharedStore.swift"], added: 164, removed: 12),
            Ask(text: "위젯을 누르면 그 할 일이 바로 열리게 해 줘",
                reply: "위젯 항목마다 todoapp://todo/<id> 링크를 달고, 앱이 받으면 그 할 일 상세 화면을 열게 했어요.",
                files: ["Widget/TodayWidget.swift", "Sources/App/TodoApp.swift"], added: 37, removed: 3),
        ], model: "claude-opus-5-5", tokens: 2_310_000, cost: 4.05, skills: ["swiftui-review": 1],
             headline: "다크 모드 색 정리와 오늘 할 일 위젯",
             points: ["의미 색으로 바꿔 두 화면 모두 글자 대비 4.5:1 이상", "오늘 할 일 3개를 보여 주는 홈 화면 위젯 추가",
                      "위젯을 누르면 그 할 일 상세 화면이 열림"]),
        Work(project: "weather-widget", tool: .claudeCode, title: "날씨 API 연결", daysAgo: 4, hour: 9, gaps: [0, 10, 10, 9], asks: [
            Ask(text: "기상청 단기예보 API 로 지금 기온을 가져와 줘",
                reply: "격자 좌표로 바꿔 단기예보를 부르고, 지금 시각에 가장 가까운 기온·하늘 상태를 꺼내는 WeatherClient 를 만들었어요.",
                files: ["Sources/Weather/WeatherClient.swift", "Sources/Weather/GridConverter.swift"], added: 154),
            Ask(text: "내 위치로 바꿔 줘. 권한 거절하면 서울로",
                reply: "위치 권한을 한 번 물어보고, 거절하거나 못 찾으면 서울 격자로 불러요.",
                files: ["Sources/Weather/LocationProvider.swift"], added: 61),
            Ask(text: "API 키를 코드에 넣지 말고 설정 파일로 빼 줘",
                reply: "키를 Secrets.xcconfig 로 옮기고 .gitignore 에 넣었어요. 예시 파일 Secrets.example.xcconfig 를 함께 두었어요.",
                files: ["Config/Secrets.example.xcconfig", ".gitignore", "Sources/Weather/WeatherClient.swift"], added: 12, removed: 3),
            Ask(text: "30분마다 새로 받게 해 줘",
                reply: "위젯 타임라인을 30분 간격으로 잡고, 같은 시각 예보는 다시 부르지 않게 캐시했어요.",
                files: ["Widget/WeatherTimeline.swift"], added: 44, removed: 8),
        ], model: "claude-sonnet-5-5", tokens: 1_120_000, cost: 1.38,
             headline: "기상청 예보 연결과 위치·키 정리",
             points: ["기상청 단기예보로 지금 기온·하늘 상태를 가져옴", "내 위치로 부르고, 권한이 없으면 서울로 함",
                      "API 키를 설정 파일로 빼고 저장소에서 제외함", "30분마다 새로 받고 같은 예보는 캐시함"]),
        Work(project: "my-blog", tool: .codex, title: "RSS 와 태그 페이지", daysAgo: 5, hour: 21, gaps: [0, 10, 6], asks: [
            Ask(text: "RSS 피드 만들어 줘",
                reply: "빌드할 때 최근 글 20개로 /rss.xml 을 만들고, 머리에 피드 주소를 알리는 링크를 넣었어요.",
                files: ["scripts/build-rss.ts", "app/layout.tsx"], added: 66, removed: 1),
            Ask(text: "태그별 글 목록 페이지도",
                reply: "글 머리말의 tags 로 /tags/<태그> 페이지를 만들고, 글 아래 태그를 누르면 그 페이지로 가게 했어요.",
                files: ["app/tags/[tag]/page.tsx", "components/TagList.tsx"], added: 88, removed: 4),
            Ask(text: "한글 태그 페이지가 404 나",
                reply: "주소에서 한글이 인코딩된 채로 비교돼서 생긴 문제였어요. 태그를 decodeURIComponent 로 풀어 비교하게 고쳤어요.",
                files: ["app/tags/[tag]/page.tsx"], added: 3, removed: 2),
        ], model: "gpt-5.5-codex", tokens: 640_000,
             headline: "RSS 피드와 태그별 글 목록 추가",
             points: ["최근 글 20개로 RSS 피드를 만듦", "태그별 글 목록 페이지 추가", "한글 태그 페이지 404 고침"]),
        Work(project: "todo-app", tool: .claudeCode, title: "할 일 앱 처음 만들기", daysAgo: 8, hour: 13, gaps: [0, 10, 10, 10], asks: [
            Ask(text: "SwiftUI 로 할 일 앱 뼈대 만들어 줘. 목록, 추가, 완료 체크까지",
                reply: "SwiftData 로 할 일을 저장하는 목록 화면, 추가 시트, 완료 체크를 만들었어요. 빌드와 실행을 확인했어요.",
                files: ["Sources/App/TodoApp.swift", "Sources/Models/Todo.swift", "Sources/Views/TodoList.swift", "Sources/Views/AddTodoSheet.swift"],
                added: 212),
            Ask(text: "할 일에 마감 날짜를 넣을 수 있게 해 줘",
                reply: "마감 날짜(선택)를 추가하고, 목록에 '오늘'·'내일'·'3일 남음'처럼 보여 줘요. 지난 건 빨간색이에요.",
                files: ["Sources/Models/Todo.swift", "Sources/Views/TodoRow.swift"], added: 54, removed: 7),
            Ask(text: "완료한 건 아래로 내리고 흐리게 해 줘",
                reply: "완료한 할 일은 목록 아래 '끝낸 일'로 모으고 흐리게 보여 줘요. 체크를 풀면 다시 위로 올라가요.",
                files: ["Sources/Views/TodoList.swift"], added: 31, removed: 12),
            Ask(text: "이 프로젝트 규칙을 CLAUDE.md 에 정리해 줘",
                reply: "SwiftUI·SwiftData, 한국어 화면 문구, 기능마다 테스트를 쓴다는 규칙을 CLAUDE.md 로 정리했어요.",
                files: ["CLAUDE.md"], added: 28),
        ], model: "claude-opus-5-5", tokens: 2_760_000, cost: 4.71,
             headline: "할 일 목록·추가·완료와 마감 날짜",
             points: ["SwiftData 로 저장하는 목록·추가·완료 체크를 만듦", "마감 날짜를 넣고 '오늘'·'3일 남음'처럼 보여 줌",
                      "끝낸 일은 아래로 모아 흐리게 함", "프로젝트 규칙을 CLAUDE.md 로 정리함"]),
        Work(project: "weather-widget", tool: .lmStudio, title: "날씨 한 줄 말 만들기", daysAgo: 11, hour: 19, gaps: [0, 5, 6], asks: [
            Ask(text: "기온이랑 비 올 확률을 보고 위젯에 넣을 한 줄 말을 만들어 줘",
                reply: "기온 구간 5개 × 비 확률 3단계로 '우산 챙기세요, 쌀쌀해요' 같은 문장 15개를 만들었어요."),
            Ask(text: "너무 길어. 12자 안으로 줄여 줘",
                reply: "'우산 꼭! 쌀쌀해요'처럼 12자 안으로 다시 썼어요."),
            Ask(text: "아침이랑 저녁에 말투를 다르게",
                reply: "아침은 '오늘은 …', 저녁은 '내일은 …'으로 시작하게 나눴어요."),
        ], model: "qwen3.5-9b", tokens: 18_000,
             headline: "위젯에 넣을 날씨 한 줄 말 정리",
             points: ["기온·비 확률 조합마다 짧은 문장 15개를 만듦", "12자 안으로 줄이고 아침·저녁 말투를 나눔"]),
        Work(project: "my-blog", tool: .codex, title: "읽기 화면 다듬기", daysAgo: 13, hour: 22, gaps: [0, 9], asks: [
            Ask(text: "글 읽는 화면 글꼴을 크게, 줄 간격은 넓게 해 줘",
                reply: "본문 글꼴을 18px, 줄 간격을 1.8 로 늘리고 한 줄 길이를 34em 으로 맞췄어요.",
                files: ["app/globals.css"], added: 14, removed: 6),
            Ask(text: "다크 모드도 되게",
                reply: "시스템 설정을 따라 바뀌고, 오른쪽 위 버튼으로 직접 고를 수도 있게 했어요.",
                files: ["app/globals.css", "components/ThemeToggle.tsx"], added: 52, removed: 3),
        ], model: "gpt-5.5-codex", tokens: 310_000,
             headline: "읽기 좋은 본문과 다크 모드",
             points: ["본문 글꼴 18px·줄 간격 1.8 로 키움", "시스템을 따르는 다크 모드와 직접 고르는 버튼 추가"]),
        Work(project: "photo-album", tool: .codex, title: "사진 앨범 첫 화면", daysAgo: 15, hour: 10, gaps: [0, 10, 10], asks: [
            Ask(text: "폴더에 있는 사진을 날짜별 격자로 보여 주는 앱 만들어 줘",
                reply: "사진의 촬영 날짜(EXIF)로 묶어 달마다 격자로 보여 주는 화면을 만들었어요. 날짜가 없는 사진은 파일 날짜를 써요.",
                files: ["src/App.tsx", "src/lib/exif.ts", "src/components/PhotoGrid.tsx"], added: 238),
            Ask(text: "사진이 많으면 느려",
                reply: "보이는 줄만 그리게 바꾸고, 미리보기는 작은 크기로 한 번 만들어 저장해 두게 했어요. 3천 장에서 첫 화면이 0.4초예요.",
                files: ["src/components/PhotoGrid.tsx", "src/lib/thumbnails.ts"], added: 96, removed: 41),
            Ask(text: "사진 누르면 크게 보고 좌우로 넘기게",
                reply: "사진을 누르면 화면 가득 보여 주고, 좌우 화살표와 스와이프로 넘기게 했어요.",
                files: ["src/components/Viewer.tsx"], added: 84),
        ], model: "gpt-5.5-codex", tokens: 1_050_000,
             headline: "날짜별 사진 격자와 크게 보기",
             points: ["촬영 날짜로 묶어 달마다 격자로 보여 줌", "보이는 줄만 그리고 미리보기를 저장해 3천 장도 빠르게 함",
                      "누르면 크게 보고 좌우로 넘기게 함"]),
        Work(project: "my-blog", tool: .codex, title: "블로그 처음 만들기", daysAgo: 20, hour: 20, gaps: [0, 10, 10], asks: [
            Ask(text: "Next.js 로 마크다운 글을 읽는 블로그 만들어 줘",
                reply: "posts 폴더의 마크다운을 읽어 글 목록과 글 페이지를 만드는 블로그를 만들었어요.",
                files: ["app/page.tsx", "app/posts/[slug]/page.tsx", "lib/posts.ts"], added: 186),
            Ask(text: "코드 블록에 색 입혀 줘",
                reply: "코드 블록에 언어별 색을 입히고 복사 버튼을 달았어요.",
                files: ["components/CodeBlock.tsx"], added: 58),
            Ask(text: "Vercel 에 올려 줘",
                reply: "Vercel 프로젝트를 만들어 main 에 올리면 자동으로 배포되게 했어요. 첫 배포가 끝났어요.",
                files: ["vercel.json"], added: 9),
        ], model: "gpt-5.5-codex", tokens: 1_420_000,
             headline: "마크다운 블로그를 만들어 배포",
             points: ["마크다운 글 목록·글 페이지를 만듦", "코드 블록 색과 복사 버튼 추가", "Vercel 자동 배포 연결"]),
        Work(project: "photo-album", tool: .codex, title: "앨범 공유 링크", daysAgo: 22, hour: 15, gaps: [0, 10], asks: [
            Ask(text: "앨범 하나를 링크로 공유하게 해 줘",
                reply: "앨범마다 읽기 전용 공유 링크를 만들고, 7일 뒤 만료되게 했어요.",
                files: ["src/lib/share.ts", "src/components/ShareButton.tsx"], added: 112, removed: 5),
            Ask(text: "만료 날짜를 고를 수 있게",
                reply: "1일·7일·30일·만료 없음 중에서 고르게 했어요.",
                files: ["src/components/ShareButton.tsx"], added: 26, removed: 8),
        ], model: "gpt-5.5-codex", tokens: 480_000,
             headline: "앨범 공유 링크와 만료 기간",
             points: ["앨범마다 읽기 전용 공유 링크를 만듦", "만료 기간을 1일·7일·30일·없음 중에서 고르게 함"]),
        Work(project: "weather-widget", tool: .claudeCode, title: "위젯 디자인", daysAgo: 26, hour: 11, gaps: [0, 10], asks: [
            Ask(text: "날씨 위젯 디자인 시안 3개 만들어 줘",
                reply: "큰 숫자형, 하늘 그림형, 시간별 막대형 시안 3개를 SwiftUI 미리보기로 만들었어요.",
                files: ["Widget/Previews/DesignA.swift", "Widget/Previews/DesignB.swift", "Widget/Previews/DesignC.swift"], added: 196),
            Ask(text: "2번으로 하자. 작은 크기도 만들어 줘",
                reply: "하늘 그림형으로 정하고 작은·중간 크기 두 가지를 만들었어요.",
                files: ["Widget/WeatherWidget.swift"], added: 88, removed: 20),
        ], model: "claude-sonnet-5-5", tokens: 690_000, cost: 0.84, skills: ["swiftui-review": 1],
             headline: "위젯 디자인을 하늘 그림형으로 정함",
             points: ["시안 3개를 만들어 하늘 그림형으로 정함", "작은·중간 크기 위젯을 만듦"]),
    ]

    // MARK: - 만들기

    static func dates(for work: Work, now: Date) -> [Date] {
        let calendar = Calendar.current
        var offsets: [Int] = []
        var total = 0
        for gap in work.gaps { total += gap; offsets.append(total) }
        if work.daysAgo == 0 {
            // 오늘: 마지막 요청이 12분 전 — 아직 일하는 중이라 "30분 쉬면 요약"을 기다리는 모습.
            let last = now.addingTimeInterval(-12 * 60)
            let start = max(calendar.startOfDay(for: now).addingTimeInterval(60), last.addingTimeInterval(-Double(total) * 60))
            return offsets.map { start.addingTimeInterval(Double($0) * 60) }
        }
        let day = calendar.date(byAdding: .day, value: -work.daysAgo, to: calendar.startOfDay(for: now))!
        let start = calendar.date(bySettingHour: work.hour, minute: 7, second: 0, of: day)!
        return offsets.map { start.addingTimeInterval(Double($0) * 60) }
    }

    static func path(_ project: String) -> String { "\(root)/\(project)" }

    public static func snapshot(now: Date = Date()) -> WorkLogSnapshot {
        var sessions: [WorkSession] = []
        for work in works {
            let dates = dates(for: work, now: now)
            let base = path(work.project)
            var prompts: [PromptEntry] = []
            var touches: [String: Int] = [:]
            for (ask, date) in zip(work.asks, dates) {
                var p = PromptEntry(date: date, text: ask.text, reply: ask.reply)
                p.files = ask.files.map { "\(base)/\($0)" }
                p.linesAdded = ask.added
                p.linesRemoved = ask.removed
                for f in p.files { touches[f, default: 0] += 1 }
                prompts.append(p)
            }
            var clock = ActiveClock()
            for d in dates { clock.tick(d) }
            let usage: ModelUsage = work.tool == .claudeCode
                ? ModelUsage(inputTokens: work.tokens / 20, outputTokens: work.tokens / 25, cacheReadTokens: work.tokens * 8 / 10,
                             cacheWriteTokens: work.tokens / 10, costUSD: work.cost)
                : ModelUsage(unsplitTokens: work.tokens)
            let edits = work.asks.reduce(0) { $0 + $1.files.count }
            let tools: [String: Int] = switch work.tool {
            case .claudeCode: ["Edit": edits * 2, "Read": work.asks.count * 5, "Bash": work.asks.count * 2, "Grep": work.asks.count]
            case .codex: ["shell": work.asks.count * 4, "apply_patch": edits]
            case .lmStudio: [:]
            }
            var session = WorkSession(
                tool: work.tool, sessionId: "demo-\(work.project)-\(work.daysAgo)", title: work.title, cwd: base, projectPath: base,
                gitBranch: work.tool == .lmStudio ? nil : "main",
                start: dates.first!, end: dates.last!.addingTimeInterval(4 * 60), activeSeconds: clock.seconds + 240,
                prompts: prompts, files: touches.map { FileTouch(path: $0.key, edits: $0.value) }.sorted { $0.path < $1.path },
                toolUses: tools, models: [work.model: usage], costUSD: work.cost,
                linesAdded: work.asks.reduce(0) { $0 + $1.added }, linesRemoved: work.asks.reduce(0) { $0 + $1.removed })
            session.skillsUsed = work.skills
            sessions.append(session)
        }
        sessions.sort { $0.end > $1.end }

        let todo = path("todo-app")
        let note = MemoryNote(path: "\(todo)/.claude/memory/project.md", name: "project", summary: "todo-app: SwiftUI + SwiftData, 화면 문구는 한국어",
                              kind: "project", body: "할 일 앱. SwiftUI + SwiftData 로 만들고 화면 문구는 한국어로 쓴다.\n\n- 알림은 마감 30분 전\n- 위젯은 App Group 으로 앱과 저장소를 나눠 쓴다",
                              modified: now.addingTimeInterval(-2 * 86_400))
        var snapshot = WorkLogSnapshot(sessions: sessions, notesByRoot: [todo: [note]], loadedAt: now)
        let ago = now.addingTimeInterval(-5 * 86_400)
        snapshot.configs = [
            todo: [
                AIConfigItem(kind: .rule, name: "CLAUDE.md", summary: "SwiftUI·SwiftData, 한국어 화면 문구, 기능마다 테스트",
                             path: "\(todo)/CLAUDE.md",
                             body: "# todo-app 규칙\n\n- SwiftUI + SwiftData 로 만든다\n- 화면 문구는 한국어로 쓴다\n- 기능을 만들면 테스트도 함께 쓴다",
                             modified: ago),
                AIConfigItem(kind: .skill, name: "write-tests", summary: "고친 기능에 맞는 XCTest 를 써 주는 스킬",
                             path: "\(todo)/.claude/skills/write-tests/SKILL.md",
                             body: "---\nname: write-tests\ndescription: 고친 기능에 맞는 XCTest 를 써 준다\n---\n\n바뀐 파일을 보고 경계 값과 실패하는 경우부터 테스트를 쓴다.",
                             modified: ago),
            ],
            path("my-blog"): [
                AIConfigItem(kind: .rule, name: "AGENTS.md", summary: "Next.js App Router, 글은 posts/ 의 마크다운",
                             path: "\(path("my-blog"))/AGENTS.md",
                             body: "# my-blog\n\n- Next.js App Router 를 쓴다\n- 글은 posts/ 폴더의 마크다운이다", modified: ago),
            ],
        ]
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        snapshot.globalConfigs = [
            AIConfigScope(title: "Claude Code 전역", path: "\(home)/.claude", items: [
                AIConfigItem(kind: .rule, name: "CLAUDE.md", summary: "답은 한국어로, 바꾸기 전에 먼저 설명하기",
                             path: "\(home)/.claude/CLAUDE.md", body: "- 답은 한국어로 한다\n- 파일을 바꾸기 전에 무엇을 바꿀지 먼저 말한다",
                             modified: ago),
                AIConfigItem(kind: .skill, name: "swiftui-review", summary: "SwiftUI 화면 코드를 읽고 고칠 점을 짚어 주는 스킬",
                             path: "\(home)/.claude/skills/swiftui-review/SKILL.md",
                             body: "---\nname: swiftui-review\ndescription: SwiftUI 화면 코드 검토\n---\n\n상태 관리, 접근성, 다크 모드를 차례로 본다.",
                             modified: ago),
            ]),
        ]
        return snapshot
    }

    /// 날마다 저장돼 있는 척하는 AI 요약. 지난 날은 마감된 것, 오늘은 요청 3개까지만 담은 것(새 요청 1개가 남음).
    public static func summaries(now: Date = Date()) -> [String: DaySummary] {
        var result: [String: DaySummary] = [:]
        let calendar = Calendar.current
        for work in works {
            let dates = dates(for: work, now: now)
            let covered = work.daysAgo == 0 ? min(3, dates.count) : dates.count
            let until = dates[covered - 1]
            let created = work.daysAgo == 0
                ? until.addingTimeInterval(2 * 60)
                : calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: until))!.addingTimeInterval(60)
            let summary = DaySummary(project: path(work.project), day: Fmt.isoDay(until), digest: "", engine: "Claude Code",
                                     headline: work.headline, points: work.points, promptCount: covered,
                                     coveredUntil: until, created: created)
            result[summary.key] = summary
        }
        return result
    }
}
