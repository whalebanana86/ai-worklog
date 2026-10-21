import Foundation

/// README 스크린샷·시연용으로 지어낸 기록 (`--demo`). 실제 기록과 보관함은 읽지도 쓰지도 않는다.
/// 날짜는 실행한 날을 기준으로 잡아서, 언제 띄워도 "오늘"부터 4주 동안 일한 모습이 나온다.
/// 그 앞 30일에는 지난달에 끝낸 프로젝트(portfolio-site)가 있어 "그 전 30일 대비"가 나온다.
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

    static let worksKO: [Work] = [
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
        // 지난달에 끝낸 프로젝트: 한눈에 보기의 "그 전 30일 대비"가 비지 않게 30일보다 앞에 둔다.
        Work(project: "portfolio-site", tool: .claudeCode, title: "포트폴리오 사이트 시작", daysAgo: 57, hour: 14, gaps: [0, 10, 10, 9], asks: [
            Ask(text: "Astro 로 내 포트폴리오 사이트 만들어 줘",
                reply: "Astro 프로젝트를 만들고 소개·작업·연락 세 쪽짜리 틀을 잡았어요. 글꼴과 색은 변수 하나로 바꿀 수 있어요.",
                files: ["src/pages/index.astro", "src/pages/work.astro", "src/pages/contact.astro", "src/styles/tokens.css"], added: 214),
            Ask(text: "첫 화면에 이름이랑 한 줄 소개를 크게",
                reply: "첫 화면 위쪽에 이름과 한 줄 소개를 크게 넣고, 아래로 내리면 최근 작업 3개가 나오게 했어요.",
                files: ["src/components/Hero.astro", "src/pages/index.astro"], added: 68, removed: 12),
            Ask(text: "휴대폰에서도 보기 좋게",
                reply: "좁은 화면에서는 메뉴를 접고 작업 카드를 한 줄에 하나씩 보여 주게 했어요.",
                files: ["src/components/Nav.astro", "src/styles/tokens.css"], added: 47, removed: 9),
            Ask(text: "GitHub Pages 에 올려 줘",
                reply: "main 에 올리면 GitHub Actions 가 만들어 Pages 에 배포하게 했어요. 첫 배포가 끝났어요.",
                files: [".github/workflows/deploy.yml", "astro.config.mjs"], added: 41, removed: 2),
        ], model: "claude-opus-5-5", tokens: 3_900_000, cost: 6.90,
             headline: "포트폴리오 사이트 틀을 만들어 배포",
             points: ["Astro 로 소개·작업·연락 세 쪽을 만듦", "첫 화면에 이름·한 줄 소개와 최근 작업 3개", "휴대폰 화면 맞춤과 GitHub Pages 자동 배포"]),
        Work(project: "portfolio-site", tool: .claudeCode, title: "작업 카드와 꼬리표 거르기", daysAgo: 52, hour: 10, gaps: [0, 9, 10], asks: [
            Ask(text: "작업마다 사진, 제목, 쓴 기술이 보이는 카드로 바꿔 줘",
                reply: "작업 목록을 마크다운 파일에서 읽어 사진·제목·기술 꼬리표가 있는 카드로 보여 주게 했어요.",
                files: ["src/components/WorkCard.astro", "src/content/config.ts", "src/pages/work.astro"], added: 132, removed: 28),
            Ask(text: "기술 꼬리표를 누르면 그것만 보이게",
                reply: "꼬리표를 누르면 그 기술을 쓴 작업만 남고, 주소에도 남아 그대로 공유할 수 있어요.",
                files: ["src/components/TagFilter.astro", "src/pages/work.astro"], added: 76, removed: 6),
            Ask(text: "사진이 늦게 떠",
                reply: "사진을 WebP 로 줄여 만들고 화면에 보일 때 불러오게 했어요. 작업 쪽 크기가 4.1MB 에서 620KB 로 줄었어요.",
                files: ["astro.config.mjs", "src/components/WorkCard.astro"], added: 19, removed: 7),
        ], model: "claude-sonnet-5-5", tokens: 1_300_000, cost: 1.70,
             headline: "작업 카드·꼬리표 거르기와 사진 줄이기",
             points: ["작업마다 사진·제목·기술 꼬리표 카드", "꼬리표로 거르고 주소로 공유", "사진을 WebP 로 줄여 쪽 크기 4.1MB → 620KB"]),
        Work(project: "portfolio-site", tool: .lmStudio, title: "자기소개 글 다듬기", daysAgo: 47, hour: 22, gaps: [0, 6, 5], asks: [
            Ask(text: "이 자기소개를 세 문장으로 줄여 줘",
                reply: "하는 일, 잘하는 것, 요즘 관심사를 한 문장씩 세 문장으로 줄였어요."),
            Ask(text: "조금 덜 딱딱하게",
                reply: "'~합니다'를 '~해요'로 바꾸고 첫 문장을 질문으로 시작하게 했어요."),
            Ask(text: "영어로도",
                reply: "같은 세 문장을 영어로 옮겼어요. 길이는 한국어판과 비슷하게 맞췄어요."),
        ], model: "qwen3.5-9b", tokens: 21_000,
             headline: "자기소개를 세 문장으로 다듬음",
             points: ["하는 일·잘하는 것·관심사 세 문장으로 줄임", "말투를 부드럽게 하고 영어판도 만듦"]),
        Work(project: "portfolio-site", tool: .codex, title: "연락 양식", daysAgo: 41, hour: 20, gaps: [0, 10, 10], asks: [
            Ask(text: "연락 쪽에 이름, 이메일, 내용 양식을 만들어 줘",
                reply: "세 칸짜리 양식을 만들고, 보내면 Formspree 로 전달되게 했어요. 빈칸이 있으면 그 칸을 빨갛게 알려 줘요.",
                files: ["src/pages/contact.astro", "src/components/ContactForm.astro"], added: 94),
            Ask(text: "스팸이 오면 어떡해",
                reply: "사람 눈에는 안 보이는 칸(허니팟)과 3초 안에 보낸 것 거르기를 넣었어요.",
                files: ["src/components/ContactForm.astro"], added: 22, removed: 3),
            Ask(text: "보내고 나면 고마워요 화면",
                reply: "보내면 양식 자리에 '고마워요, 이틀 안에 답할게요' 안내가 뜨게 했어요.",
                files: ["src/components/ContactForm.astro", "src/pages/thanks.astro"], added: 31, removed: 4),
        ], model: "gpt-5.5-codex", tokens: 640_000,
             headline: "연락 양식과 스팸 거르기",
             points: ["이름·이메일·내용 양식을 Formspree 로 보냄", "허니팟 칸과 3초 거르기로 스팸 막음", "보낸 뒤 고마워요 안내"]),
        Work(project: "portfolio-site", tool: .claudeCode, title: "속도 점검과 마무리", daysAgo: 36, hour: 15, gaps: [0, 10, 8, 10], asks: [
            Ask(text: "Lighthouse 점수 올려 줘",
                reply: "글꼴을 미리 불러오고 쓰지 않는 CSS 를 빼서 성능 점수를 71 에서 98 로 올렸어요.",
                files: ["src/layouts/Base.astro", "src/styles/tokens.css"], added: 18, removed: 46),
            Ask(text: "다크 모드 추가",
                reply: "시스템 설정을 따르고, 오른쪽 위 버튼으로 바꿀 수 있게 했어요. 고른 값은 기억해요.",
                files: ["src/components/ThemeToggle.astro", "src/styles/tokens.css"], added: 63, removed: 5),
            Ask(text: "공유하면 미리보기 그림이 나오게",
                reply: "쪽마다 제목이 들어간 미리보기 그림(OG 이미지)을 사이트를 만들 때 함께 만들게 했어요.",
                files: ["src/pages/og/[slug].png.ts", "src/layouts/Base.astro"], added: 88, removed: 2),
            Ask(text: "깨진 링크 있는지 봐 줘",
                reply: "링크 검사를 돌려 깨진 링크 2개를 고쳤어요. 배포할 때마다 검사하게 했어요.",
                files: [".github/workflows/deploy.yml", "src/pages/work.astro"], added: 12, removed: 3),
        ], model: "claude-opus-5-5", tokens: 4_300_000, cost: 7.40,
             headline: "속도 98점과 다크 모드로 마무리",
             points: ["Lighthouse 성능 71 → 98", "다크 모드와 공유 미리보기 그림", "깨진 링크 2개를 고치고 배포 때마다 검사"]),
    ]

    /// 한국어가 아닌 화면에서 쓰는 영어 시연 기록. 날짜·간격·고친 파일은 한국어판과 같다.
    static let worksEN: [Work] = [
        Work(project: "todo-app", tool: .claudeCode, title: "Due-date reminders and app badge", daysAgo: 0, hour: 10, gaps: [0, 9, 10, 10], asks: [
            Ask(text: "Send a reminder 30 minutes before a to-do is due",
                reply: "Added a NotificationScheduler that books a local notification 30 minutes before the due time whenever a to-do is saved. Changing the due date reschedules it.",
                files: ["Sources/Notifications/NotificationScheduler.swift", "Sources/Models/TodoStore.swift"], added: 86, removed: 4),
            Ask(text: "If notifications are denied, show a hint that opens Settings",
                reply: "When permission is off, a banner appears above the list; tapping it opens the Notifications page in System Settings.",
                files: ["Sources/Views/PermissionBanner.swift"], added: 42),
            Ask(text: "Add tests for the reminders too",
                reply: "Added 6 tests for reminder timing, skipping overdue to-dos and rescheduling on due-date changes. All pass.",
                files: ["Tests/NotificationSchedulerTests.swift"], added: 71),
            Ask(text: "Show today's remaining to-dos on the app icon badge",
                reply: "The app icon badge now shows how many to-dos are due today, and disappears when they're all done.",
                files: ["Sources/App/TodoApp.swift", "Sources/Models/TodoStore.swift"], added: 23, removed: 2),
        ], model: "claude-opus-5-5", tokens: 1_840_000, cost: 3.12, skills: ["write-tests": 1],
             headline: "Added due-date reminders and a permission hint",
             points: ["Local reminder 30 min before due, rescheduled when the due date changes", "Banner that opens Settings when notifications are off",
                      "6 tests for reminder timing, all passing"]),
        Work(project: "my-blog", tool: .codex, title: "Post search", daysAgo: 1, hour: 20, gaps: [0, 10, 8], asks: [
            Ask(text: "Let me search posts by title and body",
                reply: "A search index (search-index.json) is built at build time, and the search box at the top finds titles and bodies instantly.",
                files: ["scripts/build-search-index.ts", "components/SearchBox.tsx"], added: 132, removed: 6),
            Ask(text: "Highlight the matched words in the results",
                reply: "Matches are wrapped in <mark>, and bodies show 40 characters around the match.",
                files: ["components/SearchResult.tsx"], added: 48, removed: 9),
            Ask(text: "Can it handle typos?",
                reply: "Titles now match with one typo allowed. Doing the same for bodies tripled the index size, so it's titles only.",
                files: ["scripts/build-search-index.ts"], added: 27, removed: 3),
        ], model: "gpt-5.5-codex", tokens: 920_000,
             headline: "Added title and body search with typo tolerance",
             points: ["Search index built at build time, instant results from the top bar", "Matched words highlighted; bodies show 40 chars around the match",
                      "Titles tolerate one typo (bodies skipped to keep the index small)"]),
        Work(project: "todo-app", tool: .claudeCode, title: "Dark mode and a Home Screen widget", daysAgo: 2, hour: 14, gaps: [0, 10, 10], asks: [
            Ask(text: "Text is hard to read in dark mode, fix the colors",
                reply: "Switched to semantic colors (background, text, accent), so contrast is at least 4.5:1 in both light and dark.",
                files: ["Resources/Colors.xcassets", "Sources/Views/TodoRow.swift"], added: 58, removed: 31),
            Ask(text: "Make a Home Screen widget showing three of today's to-dos",
                reply: "Added a widget with three of today's to-dos and the remaining count. The app and widget share storage through an App Group.",
                files: ["Widget/TodayWidget.swift", "Sources/Models/SharedStore.swift"], added: 164, removed: 12),
            Ask(text: "Tapping a widget item should open that to-do",
                reply: "Each widget row links to todoapp://todo/<id>, and the app opens that to-do's detail screen.",
                files: ["Widget/TodayWidget.swift", "Sources/App/TodoApp.swift"], added: 37, removed: 3),
        ], model: "claude-opus-5-5", tokens: 2_310_000, cost: 4.05, skills: ["swiftui-review": 1],
             headline: "Dark mode colors and a today widget",
             points: ["Semantic colors with 4.5:1+ contrast in both modes", "Home Screen widget showing three of today's to-dos",
                      "Tapping a widget row opens that to-do"]),
        Work(project: "weather-widget", tool: .claudeCode, title: "Weather API hookup", daysAgo: 4, hour: 9, gaps: [0, 10, 10, 9], asks: [
            Ask(text: "Get the current temperature from the forecast API",
                reply: "Built a WeatherClient that converts coordinates to the forecast grid and picks the temperature and sky closest to now.",
                files: ["Sources/Weather/WeatherClient.swift", "Sources/Weather/GridConverter.swift"], added: 154),
            Ask(text: "Use my location, fall back to Seoul if denied",
                reply: "It asks for location once and falls back to Seoul if denied or unavailable.",
                files: ["Sources/Weather/LocationProvider.swift"], added: 61),
            Ask(text: "Move the API key out of the code into a config file",
                reply: "Moved the key into Secrets.xcconfig, added it to .gitignore, and left a Secrets.example.xcconfig.",
                files: ["Config/Secrets.example.xcconfig", ".gitignore", "Sources/Weather/WeatherClient.swift"], added: 12, removed: 3),
            Ask(text: "Refresh every 30 minutes",
                reply: "The widget timeline refreshes every 30 minutes and caches forecasts for the same hour.",
                files: ["Widget/WeatherTimeline.swift"], added: 44, removed: 8),
        ], model: "claude-sonnet-5-5", tokens: 1_120_000, cost: 1.38,
             headline: "Hooked up the forecast API, location and keys",
             points: ["Current temperature and sky from the forecast API", "Uses your location, Seoul if permission is off",
                      "API key moved to a config file and kept out of git", "Refreshes every 30 min with caching"]),
        Work(project: "my-blog", tool: .codex, title: "RSS and tag pages", daysAgo: 5, hour: 21, gaps: [0, 10, 6], asks: [
            Ask(text: "Add an RSS feed",
                reply: "/rss.xml is built from the latest 20 posts, with a feed link in the page head.",
                files: ["scripts/build-rss.ts", "app/layout.tsx"], added: 66, removed: 1),
            Ask(text: "And a post list per tag",
                reply: "Pages at /tags/<tag> are built from each post's tags, and tags under a post link there.",
                files: ["app/tags/[tag]/page.tsx", "components/TagList.tsx"], added: 88, removed: 4),
            Ask(text: "Tag pages with spaces give a 404",
                reply: "The tag was compared while still URL-encoded. It's now decoded with decodeURIComponent first.",
                files: ["app/tags/[tag]/page.tsx"], added: 3, removed: 2),
        ], model: "gpt-5.5-codex", tokens: 640_000,
             headline: "Added an RSS feed and tag pages",
             points: ["RSS feed from the latest 20 posts", "Post list page for each tag", "Fixed 404 on tags with spaces"]),
        Work(project: "todo-app", tool: .claudeCode, title: "Starting the to-do app", daysAgo: 8, hour: 13, gaps: [0, 10, 10, 10], asks: [
            Ask(text: "Scaffold a SwiftUI to-do app: list, add, check off",
                reply: "Built a list screen backed by SwiftData, an add sheet and check-off. Builds and runs.",
                files: ["Sources/App/TodoApp.swift", "Sources/Models/Todo.swift", "Sources/Views/TodoList.swift", "Sources/Views/AddTodoSheet.swift"],
                added: 212),
            Ask(text: "Let to-dos have a due date",
                reply: "Added an optional due date, shown as 'Today', 'Tomorrow' or '3 days left'. Overdue ones turn red.",
                files: ["Sources/Models/Todo.swift", "Sources/Views/TodoRow.swift"], added: 54, removed: 7),
            Ask(text: "Move finished ones to the bottom and dim them",
                reply: "Finished to-dos gather under 'Done' at the bottom, dimmed. Unchecking moves them back up.",
                files: ["Sources/Views/TodoList.swift"], added: 31, removed: 12),
            Ask(text: "Write this project's rules into CLAUDE.md",
                reply: "Wrote CLAUDE.md: SwiftUI and SwiftData, plain UI copy, and tests for every feature.",
                files: ["CLAUDE.md"], added: 28),
        ], model: "claude-opus-5-5", tokens: 2_760_000, cost: 4.71,
             headline: "To-do list, add and check-off with due dates",
             points: ["List, add sheet and check-off backed by SwiftData", "Due dates shown as 'Today' or '3 days left'",
                      "Finished items dimmed at the bottom", "Project rules written to CLAUDE.md"]),
        Work(project: "weather-widget", tool: .lmStudio, title: "One-line weather messages", daysAgo: 11, hour: 19, gaps: [0, 5, 6], asks: [
            Ask(text: "Write one-line widget messages from temperature and chance of rain",
                reply: "Wrote 15 lines for 5 temperature ranges × 3 rain levels, like 'Grab an umbrella, it's chilly'."),
            Ask(text: "Too long. Keep them under 20 characters",
                reply: "Rewrote them under 20 characters, like 'Umbrella! Chilly'."),
            Ask(text: "Use a different tone in the morning and evening",
                reply: "Morning lines start with 'Today…', evening lines with 'Tomorrow…'."),
        ], model: "qwen3.5-9b", tokens: 18_000,
             headline: "Short weather lines for the widget",
             points: ["15 short lines for each temperature and rain combination", "Trimmed to 20 characters with morning and evening tones"]),
        Work(project: "my-blog", tool: .codex, title: "Polishing the reading view", daysAgo: 13, hour: 22, gaps: [0, 9], asks: [
            Ask(text: "Bigger font and more line spacing in the post view",
                reply: "Body text is now 18px with 1.8 line height and a 34em measure.",
                files: ["app/globals.css"], added: 14, removed: 6),
            Ask(text: "Dark mode too",
                reply: "It follows the system setting, and a button at the top right lets you pick.",
                files: ["app/globals.css", "components/ThemeToggle.tsx"], added: 52, removed: 3),
        ], model: "gpt-5.5-codex", tokens: 310_000,
             headline: "More readable posts and dark mode",
             points: ["Body text 18px with 1.8 line height", "Dark mode that follows the system, plus a toggle"]),
        Work(project: "photo-album", tool: .codex, title: "Photo album first screen", daysAgo: 15, hour: 10, gaps: [0, 10, 10], asks: [
            Ask(text: "Make an app that shows photos in a folder as a grid by date",
                reply: "Built a grid grouped by month using each photo's capture date (EXIF), falling back to the file date.",
                files: ["src/App.tsx", "src/lib/exif.ts", "src/components/PhotoGrid.tsx"], added: 238),
            Ask(text: "It's slow with lots of photos",
                reply: "Only visible rows are drawn now, and thumbnails are generated once and cached. First screen takes 0.4s with 3,000 photos.",
                files: ["src/components/PhotoGrid.tsx", "src/lib/thumbnails.ts"], added: 96, removed: 41),
            Ask(text: "Tap a photo to view it large and swipe between them",
                reply: "Tapping a photo shows it full screen; arrow keys and swipes move between photos.",
                files: ["src/components/Viewer.tsx"], added: 84),
        ], model: "gpt-5.5-codex", tokens: 1_050_000,
             headline: "Photo grid by date with a full-screen viewer",
             points: ["Photos grouped by month using capture dates", "Visible rows only and cached thumbnails: fast with 3,000 photos",
                      "Full-screen viewer with swipe"]),
        Work(project: "my-blog", tool: .codex, title: "Starting the blog", daysAgo: 20, hour: 20, gaps: [0, 10, 10], asks: [
            Ask(text: "Build a Next.js blog that reads Markdown posts",
                reply: "Built a blog that reads Markdown from the posts folder into a post list and post pages.",
                files: ["app/page.tsx", "app/posts/[slug]/page.tsx", "lib/posts.ts"], added: 186),
            Ask(text: "Color the code blocks",
                reply: "Code blocks get language-aware highlighting and a copy button.",
                files: ["components/CodeBlock.tsx"], added: 58),
            Ask(text: "Deploy it to Vercel",
                reply: "Created a Vercel project that deploys on every push to main. The first deploy is live.",
                files: ["vercel.json"], added: 9),
        ], model: "gpt-5.5-codex", tokens: 1_420_000,
             headline: "Built a Markdown blog and deployed it",
             points: ["Markdown post list and post pages", "Highlighted code blocks with copy", "Auto-deploy on Vercel"]),
        Work(project: "photo-album", tool: .codex, title: "Album share links", daysAgo: 22, hour: 15, gaps: [0, 10], asks: [
            Ask(text: "Let me share an album with a link",
                reply: "Each album can get a read-only share link that expires in 7 days.",
                files: ["src/lib/share.ts", "src/components/ShareButton.tsx"], added: 112, removed: 5),
            Ask(text: "Let me choose when it expires",
                reply: "You can pick 1 day, 7 days, 30 days or never.",
                files: ["src/components/ShareButton.tsx"], added: 26, removed: 8),
        ], model: "gpt-5.5-codex", tokens: 480_000,
             headline: "Album share links with expiry",
             points: ["Read-only share link per album", "Expiry of 1, 7 or 30 days, or never"]),
        Work(project: "weather-widget", tool: .claudeCode, title: "Widget design", daysAgo: 26, hour: 11, gaps: [0, 10], asks: [
            Ask(text: "Make three design drafts for the weather widget",
                reply: "Made three SwiftUI previews: big number, sky illustration and hourly bars.",
                files: ["Widget/Previews/DesignA.swift", "Widget/Previews/DesignB.swift", "Widget/Previews/DesignC.swift"], added: 196),
            Ask(text: "Let's go with #2. Add a small size too",
                reply: "Went with the sky illustration and built small and medium sizes.",
                files: ["Widget/WeatherWidget.swift"], added: 88, removed: 20),
        ], model: "claude-sonnet-5-5", tokens: 690_000, cost: 0.84, skills: ["swiftui-review": 1],
             headline: "Picked the sky-illustration widget design",
             points: ["Three drafts, sky illustration chosen", "Small and medium widget sizes"]),
        Work(project: "portfolio-site", tool: .claudeCode, title: "Starting the portfolio site", daysAgo: 57, hour: 14, gaps: [0, 10, 10, 9], asks: [
            Ask(text: "Build my portfolio site with Astro",
                reply: "Set up an Astro project with three pages: About, Work and Contact. Fonts and colors come from one set of variables.",
                files: ["src/pages/index.astro", "src/pages/work.astro", "src/pages/contact.astro", "src/styles/tokens.css"], added: 214),
            Ask(text: "Put my name and a one-line intro big on the home page",
                reply: "The home page now opens with your name and intro in large type, with your three latest projects below.",
                files: ["src/components/Hero.astro", "src/pages/index.astro"], added: 68, removed: 12),
            Ask(text: "Make it look good on phones",
                reply: "On narrow screens the menu collapses and project cards stack one per row.",
                files: ["src/components/Nav.astro", "src/styles/tokens.css"], added: 47, removed: 9),
            Ask(text: "Deploy it to GitHub Pages",
                reply: "Pushing to main now builds with GitHub Actions and deploys to Pages. The first deploy is done.",
                files: [".github/workflows/deploy.yml", "astro.config.mjs"], added: 41, removed: 2),
        ], model: "claude-opus-5-5", tokens: 3_900_000, cost: 6.90,
             headline: "Portfolio site built and deployed",
             points: ["Astro site with About, Work and Contact pages", "Name, intro and three latest projects on the home page",
                      "Phone layout and automatic GitHub Pages deploys"]),
        Work(project: "portfolio-site", tool: .claudeCode, title: "Project cards and tag filter", daysAgo: 52, hour: 10, gaps: [0, 9, 10], asks: [
            Ask(text: "Turn each project into a card with a photo, title and the tech used",
                reply: "Projects are read from Markdown files and shown as cards with a photo, title and tech tags.",
                files: ["src/components/WorkCard.astro", "src/content/config.ts", "src/pages/work.astro"], added: 132, removed: 28),
            Ask(text: "Clicking a tag should show only those projects",
                reply: "Clicking a tag filters to the projects that use it, and the filter stays in the URL so you can share it.",
                files: ["src/components/TagFilter.astro", "src/pages/work.astro"], added: 76, removed: 6),
            Ask(text: "The photos load slowly",
                reply: "Photos are now resized to WebP and load as they scroll into view. The Work page went from 4.1MB to 620KB.",
                files: ["astro.config.mjs", "src/components/WorkCard.astro"], added: 19, removed: 7),
        ], model: "claude-sonnet-5-5", tokens: 1_300_000, cost: 1.70,
             headline: "Project cards, tag filter and lighter photos",
             points: ["Cards with photo, title and tech tags", "Filter by tag, shareable by URL", "WebP photos: page size 4.1MB → 620KB"]),
        Work(project: "portfolio-site", tool: .lmStudio, title: "Polishing the bio", daysAgo: 47, hour: 22, gaps: [0, 6, 5], asks: [
            Ask(text: "Cut this bio down to three sentences",
                reply: "Trimmed it to three sentences: what you do, what you're good at, and what you're into lately."),
            Ask(text: "A bit less stiff",
                reply: "Loosened the tone and opened with a question."),
            Ask(text: "Now in Korean too",
                reply: "Translated the same three sentences into Korean, keeping the length about the same."),
        ], model: "qwen3.5-9b", tokens: 21_000,
             headline: "Bio trimmed to three sentences",
             points: ["Three sentences: work, strengths, interests", "Friendlier tone, plus a Korean version"]),
        Work(project: "portfolio-site", tool: .codex, title: "Contact form", daysAgo: 41, hour: 20, gaps: [0, 10, 10], asks: [
            Ask(text: "Add a contact form with name, email and message",
                reply: "Added a three-field form that sends through Formspree. Empty fields are highlighted in red.",
                files: ["src/pages/contact.astro", "src/components/ContactForm.astro"], added: 94),
            Ask(text: "What about spam?",
                reply: "Added a hidden honeypot field and a filter that drops anything sent within 3 seconds.",
                files: ["src/components/ContactForm.astro"], added: 22, removed: 3),
            Ask(text: "Show a thank-you after sending",
                reply: "After sending, the form is replaced with “Thanks, I'll reply within two days.”",
                files: ["src/components/ContactForm.astro", "src/pages/thanks.astro"], added: 31, removed: 4),
        ], model: "gpt-5.5-codex", tokens: 640_000,
             headline: "Contact form with spam filtering",
             points: ["Name, email and message form via Formspree", "Honeypot field and 3-second filter against spam", "Thank-you message after sending"]),
        Work(project: "portfolio-site", tool: .claudeCode, title: "Speed check and finishing touches", daysAgo: 36, hour: 15, gaps: [0, 10, 8, 10], asks: [
            Ask(text: "Raise the Lighthouse score",
                reply: "Preloaded the fonts and removed unused CSS; the performance score went from 71 to 98.",
                files: ["src/layouts/Base.astro", "src/styles/tokens.css"], added: 18, removed: 46),
            Ask(text: "Add dark mode",
                reply: "It follows the system setting, with a toggle at the top right that remembers your choice.",
                files: ["src/components/ThemeToggle.astro", "src/styles/tokens.css"], added: 63, removed: 5),
            Ask(text: "Show a preview image when a page is shared",
                reply: "Each page now gets a preview image (OG image) with its title, generated when the site builds.",
                files: ["src/pages/og/[slug].png.ts", "src/layouts/Base.astro"], added: 88, removed: 2),
            Ask(text: "Check for broken links",
                reply: "Ran a link check and fixed 2 broken links. It now runs on every deploy.",
                files: [".github/workflows/deploy.yml", "src/pages/work.astro"], added: 12, removed: 3),
        ], model: "claude-opus-5-5", tokens: 4_300_000, cost: 7.40,
             headline: "Speed score 98 and dark mode to wrap up",
             points: ["Lighthouse performance 71 → 98", "Dark mode and share preview images", "Fixed 2 broken links; checked on every deploy"]),
    ]

    /// 화면 언어에 맞는 시연 기록 (일본어 화면도 영어판을 쓴다).
    static var works: [Work] { Loc.language == .ko ? worksKO : worksEN }

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
        let ko = Loc.language == .ko
        let note = MemoryNote(path: "\(todo)/.claude/memory/project.md", name: "project",
                              summary: ko ? "todo-app: SwiftUI + SwiftData, 화면 문구는 한국어" : "todo-app: SwiftUI + SwiftData, plain UI copy",
                              kind: "project",
                              body: ko ? "할 일 앱. SwiftUI + SwiftData 로 만들고 화면 문구는 한국어로 쓴다.\n\n- 알림은 마감 30분 전\n- 위젯은 App Group 으로 앱과 저장소를 나눠 쓴다"
                                  : "A to-do app built with SwiftUI + SwiftData.\n\n- Reminders fire 30 minutes before due\n- The widget shares storage with the app through an App Group",
                              modified: now.addingTimeInterval(-2 * 86_400))
        var snapshot = WorkLogSnapshot(sessions: sessions, notesByRoot: [todo: [note]], loadedAt: now)
        let ago = now.addingTimeInterval(-5 * 86_400)
        // 지어낸 설정 파일: (한국어, 영어) 두 가지로 적어 두고 화면 언어에 맞는 쪽을 쓴다.
        func t(_ korean: String, _ english: String) -> String { ko ? korean : english }
        snapshot.configs = [
            todo: [
                AIConfigItem(kind: .rule, name: "CLAUDE.md", summary: t("SwiftUI·SwiftData, 한국어 화면 문구, 기능마다 테스트", "SwiftUI·SwiftData, plain UI copy, tests for every feature"),
                             path: "\(todo)/CLAUDE.md",
                             body: t("# todo-app 규칙\n\n- SwiftUI + SwiftData 로 만든다\n- 화면 문구는 한국어로 쓴다\n- 기능을 만들면 테스트도 함께 쓴다",
                                     "# todo-app rules\n\n- Build with SwiftUI + SwiftData\n- Keep UI copy short and plain\n- Write tests along with every feature"),
                             modified: ago),
                AIConfigItem(kind: .skill, name: "write-tests", summary: t("고친 기능에 맞는 XCTest 를 써 주는 스킬", "Writes XCTest cases for the code you changed"),
                             path: "\(todo)/.claude/skills/write-tests/SKILL.md",
                             body: t("---\nname: write-tests\ndescription: 고친 기능에 맞는 XCTest 를 써 준다\n---\n\n바뀐 파일을 보고 경계 값과 실패하는 경우부터 테스트를 쓴다.",
                                     "---\nname: write-tests\ndescription: Writes XCTest cases for changed code\n---\n\nLook at the changed files and start with edge cases and failure paths."),
                             modified: ago),
            ],
            path("my-blog"): [
                AIConfigItem(kind: .rule, name: "AGENTS.md", summary: t("Next.js App Router, 글은 posts/ 의 마크다운", "Next.js App Router, posts are Markdown in posts/"),
                             path: "\(path("my-blog"))/AGENTS.md",
                             body: t("# my-blog\n\n- Next.js App Router 를 쓴다\n- 글은 posts/ 폴더의 마크다운이다",
                                     "# my-blog\n\n- Use the Next.js App Router\n- Posts are Markdown files in posts/"), modified: ago),
            ],
        ]
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        snapshot.globalConfigs = [
            AIConfigScope(title: L("Claude Code 전역"), path: "\(home)/.claude", items: [
                AIConfigItem(kind: .rule, name: "CLAUDE.md", summary: t("답은 한국어로, 바꾸기 전에 먼저 설명하기", "Explain before changing files"),
                             path: "\(home)/.claude/CLAUDE.md",
                             body: t("- 답은 한국어로 한다\n- 파일을 바꾸기 전에 무엇을 바꿀지 먼저 말한다", "- Say what you will change before editing files"),
                             modified: ago),
                AIConfigItem(kind: .skill, name: "swiftui-review", summary: t("SwiftUI 화면 코드를 읽고 고칠 점을 짚어 주는 스킬", "Reviews SwiftUI view code and points out fixes"),
                             path: "\(home)/.claude/skills/swiftui-review/SKILL.md",
                             body: t("---\nname: swiftui-review\ndescription: SwiftUI 화면 코드 검토\n---\n\n상태 관리, 접근성, 다크 모드를 차례로 본다.",
                                     "---\nname: swiftui-review\ndescription: Review SwiftUI view code\n---\n\nCheck state handling, accessibility and dark mode in turn."),
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
