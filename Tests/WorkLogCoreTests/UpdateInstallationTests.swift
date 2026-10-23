import XCTest
import CryptoKit
@testable import WorkLogCore

final class UpdateInstallationTests: XCTestCase {
    func workspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("AIWorkLogUpdate-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    func testDigestRejectsCorruptionAndSizeMismatch() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("update.zip")
        let data = Data("original release bytes".utf8)
        try data.write(to: file)
        let digest = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try UpdateArchive.verify(file, digest: digest, size: Int64(data.count))
        XCTAssertThrowsError(try UpdateArchive.verify(file, digest: digest, size: 2))
        try Data("corrupted release byte".utf8).write(to: file)
        XCTAssertThrowsError(try UpdateArchive.verify(file, digest: digest, size: Int64(data.count)))
        XCTAssertNil(UpdateArchive.sha256Digest("sha256:abc"))
        XCTAssertNil(UpdateArchive.sha256Digest("md5:" + String(repeating: "a", count: 64)))
    }

    func testRejectsTraversalAndSymlinksBeforeExtraction() throws {
        for entry in ["/tmp/escape", "이걸내가.app/../escape", "other.app/Contents/Info.plist", "__MACOSX/../../escape", "이걸내가.app/a\\b"] {
            XCTAssertFalse(UpdateArchive.isSafeEntry(entry), entry)
        }
        XCTAssertTrue(UpdateArchive.isSafeEntry("이걸내가.app/Contents/Info.plist"))
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("이걸내가.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: app.appendingPathComponent("escape"), withDestinationURL: URL(fileURLWithPath: "/tmp"))
        let zip = root.appendingPathComponent("linked.zip")
        _ = try UpdateProcess.output("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
        let destination = root.appendingPathComponent("unpacked")
        XCTAssertThrowsError(try UpdateArchive.extract(zip, into: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testSuccessfulReplacementAndRollbackOnRestartFailure() throws {
        for failRestart in [false, true] {
            let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
            let target = root.appendingPathComponent("Installed.app")
            let plan = UpdatePlan(target: target, workspace: root, version: "1.6.0", team: nil, parentPID: getpid())
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try Data("old".utf8).write(to: target.appendingPathComponent("version"))
            try FileManager.default.createDirectory(at: plan.candidate, withIntermediateDirectories: false)
            try Data("new".utf8).write(to: plan.candidate.appendingPathComponent("version"))
            var restarted = false
            let transaction = {
                try UpdateInstallation.replace(plan, validate: {
                    XCTAssertEqual(try String(contentsOf: $0.appendingPathComponent("version")), "new")
                }, restart: { url in
                    restarted = true
                    XCTAssertEqual(url, target)
                    if failRestart { throw AppUpdateError.restartFailed }
                })
            }
            if failRestart { XCTAssertThrowsError(try transaction()) }
            else { try transaction() }
            XCTAssertTrue(restarted)
            XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("version")), failRestart ? "old" : "new")
        }
    }

    func testInvalidCandidateNeverMovesOriginal() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Installed.app")
        let plan = UpdatePlan(target: target, workspace: root, version: "1.6.0", team: nil, parentPID: getpid())
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        XCTAssertThrowsError(try UpdateInstallation.replace(plan, validate: { _ in throw AppUpdateError.invalidSignature }, restart: { _ in XCTFail("Must not restart") }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.backup.path))
    }

    func testInvalidWorkspaceCannotBeCleanedUpByHelper() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let plan = UpdatePlan(target: root.appendingPathComponent("Installed.app"), workspace: URL(fileURLWithPath: NSHomeDirectory()), version: "1.6.0", team: nil, parentPID: getpid())
        XCTAssertThrowsError(try plan.validatePaths())
    }
    /// Opt-in integration: the public release is downloaded outside the test, then
    /// validation and replacement run exclusively on disposable app copies.
    func testPublishedReleaseInstallsAndRollsBackInIsolation() throws {
        guard let fixture = ProcessInfo.processInfo.environment["AIWORKLOG_UPDATE_FIXTURE"] else {
            throw XCTSkip("Set AIWORKLOG_UPDATE_FIXTURE to a downloaded release fixture")
        }
        let source = URL(fileURLWithPath: fixture)
        let release = try JSONDecoder().decode(AppRelease.self, from: Data(contentsOf: source.appendingPathComponent("release.json")))
        let asset = try XCTUnwrap(release.updateAsset)
        let work = try workspace(); defer { try? FileManager.default.removeItem(at: work) }
        let zip = source.appendingPathComponent("update.zip")
        try UpdateArchive.verify(zip, digest: asset.digest, size: asset.size)
        let app = try UpdateArchive.extract(zip, into: work.appendingPathComponent("unpacked"))
        try UpdateAppValidation.validate(app, version: release.version, team: nil)
        XCTAssertThrowsError(try UpdateAppValidation.validate(app, version: release.version, team: "DIFFERENT-TEAM"))

        for failRestart in [false, true] {
            let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/AIWorkLog-update-test-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let current = root.appendingPathComponent("이걸내가.app")
            try FileManager.default.copyItem(at: app, to: current)
            let plist = current.appendingPathComponent("Contents/Info.plist")
            var info = try UpdateAppValidation.info(current)
            info["CFBundleShortVersionString"] = "1.4.0"
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
            _ = try UpdateProcess.output("/usr/bin/codesign", ["--force", "--sign", "-", current.path])
            let plan = try UpdateInstallation.prepare(app: app, target: current, workspace: work, version: release.version)
            var restarted = false
            let install = {
                try UpdateInstallation.replace(plan, validate: { try UpdateAppValidation.validate($0, version: release.version, team: nil) }, restart: { url in
                    restarted = true
                    XCTAssertEqual(try UpdateAppValidation.info(url)["CFBundleShortVersionString"] as? String, release.version)
                    if failRestart { throw AppUpdateError.restartFailed }
                })
            }
            if failRestart { XCTAssertThrowsError(try install()) }
            else { try install() }
            XCTAssertTrue(restarted)
            XCTAssertEqual(try UpdateAppValidation.info(current)["CFBundleShortVersionString"] as? String, failRestart ? "1.4.0" : release.version)
            _ = try UpdateAppValidation.signingTeam(current)
        }
    }

    func testCleanupRemovesStagingButKeepsInstalledAppAndRecoveryBackup() throws {
        let fm = FileManager.default
        let work = try workspace()
        let target = work.deletingLastPathComponent().appendingPathComponent("InstalledCleanupTest-" + UUID().uuidString + ".app")
        let plan = UpdatePlan(target: target, workspace: work, version: "1.7.1", team: nil, parentPID: getpid())
        defer {
            for url in [work, target, plan.candidate, plan.backup] { try? fm.removeItem(at: url) }
        }
        for url in [target, plan.candidate, plan.backup] { try fm.createDirectory(at: url, withIntermediateDirectories: false) }
        try UpdateInstallation.cleanupTemporaryFiles(plan)
        XCTAssertFalse(fm.fileExists(atPath: work.path))
        XCTAssertFalse(fm.fileExists(atPath: plan.candidate.path))
        XCTAssertTrue(fm.fileExists(atPath: target.path))
        XCTAssertTrue(fm.fileExists(atPath: plan.backup.path))
    }

}
