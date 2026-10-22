import Foundation
import WorkLogCore

// `AIWorkLog cli --quiet` 처럼 부르면 창을 띄우지 않고 터미널 명령으로 동작한다.
// 설치 스크립트와 자동 보관이 쓴다. 실행 파일을 하나로 합쳐 앱 용량을 줄이려는 것.
let arguments = CommandLine.arguments
if arguments.count == 3, arguments[1] == "--install-update" {
    Loc.language = AppLanguage.saved ?? .system
    exit(UpdateInstallation.runHelper(planURL: URL(fileURLWithPath: arguments[2])))
}
if arguments.count > 1, arguments[1] == "cli" {
    exit(WorkLogCommand.run(Array(arguments.dropFirst(2))))
}
// 화면 언어: 설정에서 고른 것, 없으면 맥 언어. 화면 확인용 `--lang en|ja|ko` 는 저장하지 않고 이번에만 쓴다.
if let i = arguments.firstIndex(of: "--lang"), i + 1 < arguments.count, let language = AppLanguage(rawValue: arguments[i + 1]) {
    Loc.language = language
} else {
    Loc.language = AppLanguage.saved ?? .system
}
AIWorkLogApp.main()
