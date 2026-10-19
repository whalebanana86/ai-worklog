import Foundation

/// 앱을 열지 않아도 6시간마다 보관함을 갱신하는 launchd 작업.
/// 설치 옵션(`build_app.sh --auto-sync`)과 앱 설정이 같은 것을 켜고 끈다.
public struct AutoSync {
    public static let label = "local.aiworklog.sync"
    public static let interval = 6 * 60 * 60

    public let agentURL: URL
    public let logURL: URL
    /// launchctl 로 올리고 내릴지. 테스트에서는 끄고 파일만 본다.
    var useLaunchctl = true

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        agentURL = home.appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
        logURL = home.appendingPathComponent("Library/Logs/AIWorkLog-sync.log")
    }

    public var isEnabled: Bool { FileManager.default.fileExists(atPath: agentURL.path) }

    /// 지금 실행 중인 프로그램으로 보관함을 갱신하는 명령.
    /// 앱 안의 실행 파일은 `cli` 를 붙여야 창 없이 돌고, 개발용 worklog-cli 는 그대로 부른다.
    public static var currentProgram: [String] {
        let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
        return Bundle.main.bundlePath.hasSuffix(".app") ? [executable, "cli", "--quiet"] : [executable, "--quiet"]
    }

    /// 등록된 작업이 부르는 명령. 꺼져 있으면 nil.
    public var registeredProgram: [String]? {
        guard let data = try? Data(contentsOf: agentURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["ProgramArguments"] as? [String]
    }

    /// 마지막으로 자동 보관이 돈 때 (기록 파일을 고친 시각).
    public var lastRun: Date? {
        (try? FileManager.default.attributesOfItem(atPath: logURL.path))?[.modificationDate] as? Date
    }

    /// 켜기. 예전에 등록한 것이 있으면 내리고 새로 올린다. 켜자마자 한 번 돈다.
    public func enable(program: [String] = AutoSync.currentProgram) throws {
        disable()
        let fm = FileManager.default
        try fm.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": program,
            "StartInterval": Self.interval,
            "RunAtLoad": true,
            "LowPriorityIO": true,
            "Nice": 10,
            "StandardOutPath": logURL.path,
            "StandardErrorPath": logURL.path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        do {
            try data.write(to: agentURL, options: .atomic)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            // 다른 프로그램 설치기가 이 폴더를 관리자(root) 것으로 만들어 두면 사용자 앱은 여기에 쓸 수 없다.
            throw AutoSyncError(description: "~/Library/LaunchAgents 폴더에 쓸 권한이 없어요. 터미널에서 "
                                + "sudo chown $USER ~/Library/LaunchAgents 를 한 번 실행한 뒤 다시 켜 주세요.")
        }
        if useLaunchctl {
            let status = Self.launchctl(["bootstrap", "gui/\(getuid())", agentURL.path])
            if status != 0 {
                try? fm.removeItem(at: agentURL)
                throw AutoSyncError(description: "launchd 에 등록하지 못했어요 (launchctl 종료 코드 \(status))")
            }
        }
    }

    /// 끄기. 꺼져 있으면 아무것도 하지 않는다.
    public func disable() {
        guard isEnabled else { return }
        if useLaunchctl { _ = Self.launchctl(["bootout", "gui/\(getuid())", agentURL.path]) }
        try? FileManager.default.removeItem(at: agentURL)
    }

    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

public struct AutoSyncError: Error, CustomStringConvertible {
    public var description: String
}
