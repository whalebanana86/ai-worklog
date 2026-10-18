import Foundation
import WorkLogCore

// 앱과 같은 코드로 기록을 읽어 터미널에 요약한다. 쓰는 법은 WorkLogCommand 참고.
exit(WorkLogCommand.run(Array(CommandLine.arguments.dropFirst())))
