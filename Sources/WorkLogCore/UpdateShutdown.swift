import Foundation

/// A termination request may be refused by AppKit. Never leave the updater busy
/// forever in that case. The caller dismisses its modal sheet before this starts.
public enum UpdateShutdown {
    @MainActor
    public static func request(
        settleNanoseconds: UInt64 = 250_000_000,
        graceNanoseconds: UInt64 = 1_000_000_000,
        terminate: @MainActor () -> Void,
        stillRunning: @MainActor () async -> Void
    ) async {
        // Give SwiftUI a run-loop turn to finish dismissing its sheet.
        try? await Task.sleep(nanoseconds: settleNanoseconds)
        terminate()
        // Successful termination never reaches this fallback in a running app.
        try? await Task.sleep(nanoseconds: graceNanoseconds)
        await stillRunning()
    }

    /// Only cancel a helper while its parent app is still alive. It cannot have
    /// begun replacing the bundle while it is waiting for this process to exit.
    @MainActor
    public static func cancelWaitingHelper(_ process: Process) async {
        if process.isRunning { process.terminate() }
        await Task.detached { process.waitUntilExit() }.value
    }

}
