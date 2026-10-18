import Foundation
import WorkLogCore

// `AIWorkLog cli --quiet` 처럼 부르면 창을 띄우지 않고 터미널 명령으로 동작한다.
// 설치 스크립트와 자동 보관이 쓴다. 실행 파일을 하나로 합쳐 앱 용량을 줄이려는 것.
let arguments = CommandLine.arguments
if arguments.count > 1, arguments[1] == "cli" {
    exit(WorkLogCommand.run(Array(arguments.dropFirst(2))))
}
AIWorkLogApp.main()
