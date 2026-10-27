import Foundation
import Security
import Darwin

public enum UpdateAppValidation {
    public static func info(_ app: URL) throws -> [String: Any] {
        guard app.pathExtension == "app", app.standardizedFileURL == app.resolvingSymlinksInPath().standardizedFileURL,
              let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "local.aiworklog",
              info["CFBundleExecutable"] as? String == "AIWorkLog" else { throw AppUpdateError.invalidApp }
        return info
    }

    public static func signingTeam(_ app: URL) throws -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), nil) == errSecSuccess
        else { throw AppUpdateError.invalidSignature }
        var raw: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &raw) == errSecSuccess,
              let info = raw as? [String: Any], info[kSecCodeInfoIdentifier as String] as? String == "local.aiworklog"
        else { throw AppUpdateError.invalidSignature }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }

    public static func validate(_ app: URL, version: String, team: String?) throws {
        let info = try self.info(app)
        guard info["CFBundleShortVersionString"] as? String == version else { throw AppUpdateError.invalidApp }
        if let minimum = info["LSMinimumSystemVersion"] as? String,
           minimum.compare(ProcessInfo.processInfo.operatingSystemVersionStringVersion, options: .numeric) == .orderedDescending {
            throw AppUpdateError.invalidApp
        }
        let actualTeam = try signingTeam(app)
        if let team, team != actualTeam { throw AppUpdateError.signingIdentityChanged }
        guard try supportsCurrentArchitecture(app.appendingPathComponent("Contents/MacOS/AIWorkLog")) else { throw AppUpdateError.invalidApp }
    }

    /// Read the Mach-O header directly; end users do not need Xcode/lipo installed.
    public static func supportsCurrentArchitecture(_ executable: URL) throws -> Bool {
        let file = try FileHandle(forReadingFrom: executable)
        defer { try? file.close() }
        guard let data = try file.read(upToCount: 4096), data.count >= 8 else { return false }
        func word(_ i: Int, little: Bool) -> UInt32 {
            let bytes = (0..<4).map { UInt32(data[i + $0]) }
            return little ? bytes[0] | bytes[1] << 8 | bytes[2] << 16 | bytes[3] << 24
                : bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]
        }
        #if arch(arm64)
        let cpu: UInt32 = 0x0100000c
        #else
        let cpu: UInt32 = 0x01000007
        #endif
        let magic = word(0, little: false)
        if magic == 0xcafebabe || magic == 0xbebafeca || magic == 0xcafebabf || magic == 0xbfbafeca {
            let little = magic == 0xbebafeca || magic == 0xbfbafeca
            let count = Int(word(4, little: little))
            let stride = magic == 0xcafebabf || magic == 0xbfbafeca ? 32 : 20
            guard count > 0, count <= 64, 8 + count * stride <= data.count else { return false }
            return (0..<count).contains { word(8 + $0 * stride, little: little) == cpu }
        }
        if magic == 0xcffaedfe || magic == 0xcefaedfe { return word(4, little: true) == cpu }
        if magic == 0xfeedfacf || magic == 0xfeedface { return word(4, little: false) == cpu }
        return false

    }
}

private extension ProcessInfo {
    var operatingSystemVersionStringVersion: String {
        let v = operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

public struct UpdatePlan: Codable, Sendable {
    public let target: URL
    public let candidate: URL
    public let backup: URL
    public let workspace: URL
    public let version: String
    public let team: String?
    public let parentPID: Int32
    public let language: String

    public init(target: URL, workspace: URL, version: String, team: String?, parentPID: Int32) {
        self.target = target.standardizedFileURL
        self.workspace = workspace.standardizedFileURL
        self.version = version
        self.team = team
        self.parentPID = parentPID
        language = Loc.language.rawValue
        let root = target.deletingLastPathComponent()
        let token = UUID().uuidString
        candidate = root.appendingPathComponent(".Igeolnaega-update-\(token).app")
        backup = root.appendingPathComponent(".Igeolnaega-backup-\(token).app")
    }

    public func validatePaths() throws {
        let root = target.deletingLastPathComponent().standardizedFileURL
        guard target.pathExtension == "app", target != candidate, target != backup, candidate != backup,
              candidate.deletingLastPathComponent().standardizedFileURL == root,
              backup.deletingLastPathComponent().standardizedFileURL == root,
              candidate.lastPathComponent.hasPrefix(".Igeolnaega-update-"),
              backup.lastPathComponent.hasPrefix(".Igeolnaega-backup-"),
              candidate.pathExtension == "app", backup.pathExtension == "app",
              root == root.resolvingSymlinksInPath().standardizedFileURL,
              workspace.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL,
              workspace.lastPathComponent.hasPrefix("AIWorkLogUpdate-"),
              workspace == workspace.resolvingSymlinksInPath().standardizedFileURL,
              AppVersion(version) != nil, parentPID > 1 else { throw AppUpdateError.invalidPlan }
    }
}

/// The replacement transaction is independent of UI/network and can be exercised in a temporary folder.
public enum UpdateInstallation {
    public static var resultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AIWorkLog/update-result.json")
    }

    public static func prepare(app: URL, target: URL, workspace: URL, version: String) throws -> UpdatePlan {
        let fm = FileManager.default
        let target = target.resolvingSymlinksInPath().standardizedFileURL
        let old = try UpdateAppValidation.info(target)
        guard let current = old["CFBundleShortVersionString"] as? String,
              let oldVersion = AppVersion(current), let newVersion = AppVersion(version), newVersion > oldVersion else { throw AppUpdateError.invalidApp }
        guard fm.isWritableFile(atPath: target.deletingLastPathComponent().path), fm.isWritableFile(atPath: target.path),
              !target.path.hasPrefix("/Volumes/"), !target.path.hasPrefix("/private/var/folders/") else { throw AppUpdateError.cannotWrite }
        let team = try UpdateAppValidation.signingTeam(target)
        try UpdateAppValidation.validate(app, version: version, team: team)
        let plan = UpdatePlan(target: target, workspace: workspace, version: version, team: team, parentPID: getpid())
        try plan.validatePaths()
        do {
            try fm.copyItem(at: app, to: plan.candidate)
            try UpdateAppValidation.validate(plan.candidate, version: version, team: team)
        } catch {
            try? fm.removeItem(at: plan.candidate)
            throw error
        }
        return plan
    }

    /// On a failed validation/restart, roll back the bundle at its original path.
    public static func replace(_ plan: UpdatePlan, validate: (URL) throws -> Void, restart: (URL) throws -> Void) throws {
        try plan.validatePaths()
        let fm = FileManager.default
        guard !fm.fileExists(atPath: plan.backup.path) else { throw AppUpdateError.invalidPlan }
        try validate(plan.candidate)
        try fm.moveItem(at: plan.target, to: plan.backup)
        do {
            try fm.moveItem(at: plan.candidate, to: plan.target)
            try validate(plan.target)
            try restart(plan.target)
        } catch {
            // Preserve the failed candidate for diagnostics, then put the original back.
            // Restoring the original must not depend on keeping the candidate.
            if fm.fileExists(atPath: plan.target.path), (try? fm.moveItem(at: plan.target, to: plan.candidate)) == nil {
                try? fm.removeItem(at: plan.target)
            }
            try fm.moveItem(at: plan.backup, to: plan.target)
            throw error
        }
    }

    /// Remove only staging files. Never remove the installed app or its rollback backup.
    public static func cleanupTemporaryFiles(_ plan: UpdatePlan) throws {
        try plan.validatePaths()
        let workspace = plan.workspace.standardizedFileURL.path
        guard !plan.target.standardizedFileURL.path.hasPrefix(workspace + "/"),
              !plan.backup.standardizedFileURL.path.hasPrefix(workspace + "/") else { throw AppUpdateError.invalidPlan }
        let fm = FileManager.default
        for url in [plan.candidate, plan.workspace] where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    /// A crash or force quit between `prepare` and the helper leaves a hidden candidate next to the app.
    /// Remove those on launch. Rollback backups are never touched.
    public static func removeLeftoverCandidates(besides target: URL) {
        let fm = FileManager.default
        let target = target.resolvingSymlinksInPath().standardizedFileURL
        let root = target.deletingLastPathComponent()
        guard target.pathExtension == "app", let names = try? fm.contentsOfDirectory(atPath: root.path) else { return }
        for name in names where name.hasPrefix(".Igeolnaega-update-") && name.hasSuffix(".app") {
            let url = root.appendingPathComponent(name)
            guard url != target, (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == false else { continue }
            try? fm.removeItem(at: url)
        }
    }

    public static func runHelper(planURL: URL) -> Int32 {
        var plan: UpdatePlan?
        do {
            let decoded = try JSONDecoder().decode(UpdatePlan.self, from: Data(contentsOf: planURL))
            Loc.language = AppLanguage(rawValue: decoded.language) ?? .system
            try decoded.validatePaths()
            plan = decoded
            let deadline = Date().addingTimeInterval(60)
            while kill(decoded.parentPID, 0) == 0 || errno == EPERM {
                guard Date() < deadline else { throw AppUpdateError.parentStillRunning }
                Thread.sleep(forTimeInterval: 0.1)
            }
            let currentInfo = try UpdateAppValidation.info(decoded.target)
            guard let text = currentInfo["CFBundleShortVersionString"] as? String,
                  let current = AppVersion(text), let next = AppVersion(decoded.version), next > current else { throw AppUpdateError.invalidApp }
            if let team = decoded.team, try UpdateAppValidation.signingTeam(decoded.target) != team {
                throw AppUpdateError.signingIdentityChanged
            }
            try replace(decoded, validate: { try UpdateAppValidation.validate($0, version: decoded.version, team: decoded.team) }, restart: {
                writeResult(nil)
                do { _ = try UpdateProcess.output("/usr/bin/open", ["-n", $0.path]) }
                catch { throw AppUpdateError.restartFailed }
            })
            _ = try? FileManager.default.trashItem(at: decoded.backup, resultingItemURL: nil)
            // Auto-sync uses the same bundle path. Records and preferences were never moved.
            try? cleanupTemporaryFiles(decoded)
            return 0
        } catch {
            writeResult(error.localizedDescription)
            if let plan {
                // Reopen the original only after the parent exited and a rollback succeeded.
                if kill(plan.parentPID, 0) != 0, errno == ESRCH,
                   (try? UpdateAppValidation.info(plan.target)) != nil {
                    _ = try? UpdateProcess.output("/usr/bin/open", ["-n", plan.target.path])
                }
                try? cleanupTemporaryFiles(plan)
            }
            return 1
        }
    }

    private static func writeResult(_ error: String?) {
        let url = resultURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let result: [String: String] = error.map { ["error": $0] } ?? ["success": "true"]
        if let data = try? JSONEncoder().encode(result) { try? data.write(to: url, options: .atomic) }
    }
}
