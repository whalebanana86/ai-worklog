// 프로세스 번호로 그 앱의 가장 큰 창 번호를 찍는다 (screencapture -l 용).  사용: swift scripts/window_id.swift <pid> [창 제목 일부]
import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 1, let pid = Int(CommandLine.arguments[1]) else { exit(2) }
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var windows = list.filter { ($0[kCGWindowOwnerPID as String] as? Int) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
// 제목을 주면 그 글자가 들어간 창만 (설정 창처럼 가장 크지 않은 창을 찍을 때).
if CommandLine.arguments.count > 2 {
    let title = CommandLine.arguments[2]
    windows = windows.filter { ($0[kCGWindowName as String] as? String)?.contains(title) == true }
}
func area(_ w: [String: Any]) -> Double {
    let r = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return (r["Width"] ?? 0) * (r["Height"] ?? 0)
}
if let id = windows.max(by: { area($0) < area($1) })?[kCGWindowNumber as String] as? Int { print(id) } else { exit(1) }
