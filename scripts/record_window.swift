// 앱 창 하나만 영상으로 찍는다 (ScreenCaptureKit, macOS 15+). 다른 창·바탕화면은 찍히지 않는다.
//   빌드: swiftc -O -parse-as-library scripts/record_window.swift -o build.noindex/record_window
//   사용: build.noindex/record_window <pid> <초> <저장할 .mp4>
// README 시연 영상: scripts/make_demo_video.sh 가 부른다.
import AppKit
import AVFoundation
import Foundation
import ScreenCaptureKit

final class Recorder: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    let finished = DispatchSemaphore(value: 0)
    var error: Error?

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finished.signal()
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        self.error = error
        finished.signal()
    }
}

@main
enum RecordWindow {
    static func main() async throws {
        // 명령줄 도구도 화면 서버에 먼저 붙어야 ScreenCaptureKit 이 돈다.
        _ = NSApplication.shared
        let args = CommandLine.arguments
        guard args.count == 4, let pid = Int32(args[1]), let seconds = Double(args[2]) else {
            print("사용: record_window <pid> <초> <저장할 .mp4>")
            exit(2)
        }
        let output = URL(fileURLWithPath: args[3])
        try? FileManager.default.removeItem(at: output)

        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let windows = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 }
        guard let window = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            print("그 프로세스의 창을 찾지 못했어요")
            exit(1)
        }

        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * 2)
        config.height = Int(window.frame.height * 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = false
        config.capturesAudio = false

        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: nil)
        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = output
        recordingConfig.outputFileType = .mp4
        recordingConfig.videoCodecType = .h264
        let recorder = Recorder()
        let recording = SCRecordingOutput(configuration: recordingConfig, delegate: recorder)
        try stream.addRecordingOutput(recording)
        try await stream.startCapture()
        try await Task.sleep(for: .seconds(seconds))
        // 기록을 떼면 파일을 마무리한다. 다 쓸 때까지 기다린 뒤 멈춘다.
        try stream.removeRecordingOutput(recording)
        let finished = recorder.finished
        _ = await Task.detached { finished.wait(timeout: .now() + 15) }.value
        try await stream.stopCapture()
        if let error = recorder.error {
            print("녹화 실패: \(error)")
            exit(1)
        }
        print(output.path)
    }
}
