// A successful install can retire old branded copies without touching the archive.
// Usage: swift scripts/retire_legacy_apps.swift <newly installed .app>
import Foundation

let fm = FileManager.default
guard CommandLine.arguments.count == 2 else { exit(2) }
let installed = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
guard installed.lastPathComponent == "이걸내가.app",
      let bundle = Bundle(url: installed), bundle.bundleIdentifier == "local.aiworklog",
      let executable = bundle.executableURL, fm.isExecutableFile(atPath: executable.path) else {
    fputs("새 앱 설치를 확인하지 못해 예전 앱을 유지합니다.\n", stderr)
    exit(1)
}
let roots = [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
for root in roots {
    let old = root.appendingPathComponent("AI 작업일지.app")
    // Only remove this product's legacy bundle, never another app with a similar name.
    guard let bundle = Bundle(url: old), bundle.bundleIdentifier == "local.aiworklog" else { continue }
    do {
        try fm.trashItem(at: old, resultingItemURL: nil)
        print("예전 이름의 앱을 휴지통으로 옮겼어요: \(old.path)")
    } catch {
        print("예전 앱은 직접 휴지통으로 옮겨 주세요: \(old.path) (\(error.localizedDescription))")
    }
}
