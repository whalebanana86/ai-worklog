import Foundation
import CryptoKit

public enum AppUpdateError: Error, LocalizedError {
    case invalidAsset, checksumMismatch, unsignedUpdate, invalidArchive, invalidApp, invalidSignature
    case signingIdentityChanged, cannotWrite, parentStillRunning, invalidPlan, restartFailed

    public var errorDescription: String? {
        switch self {
        case .invalidAsset: return L("자동 설치할 수 있는 업데이트 파일이 없어요. 다운로드 페이지에서 설치해 주세요.")
        case .checksumMismatch: return L("다운로드한 파일의 검증 값이 맞지 않아요. 다시 다운로드해 주세요.")
        case .unsignedUpdate: return L("업데이트 파일의 배포 서명이 맞지 않아요. 다운로드 페이지에서 설치해 주세요.")
        case .invalidArchive: return L("업데이트 압축 파일이 올바르지 않아요.")
        case .invalidApp: return L("업데이트 앱의 이름, 버전 또는 실행 환경을 확인하지 못했어요.")
        case .invalidSignature: return L("업데이트 앱의 서명을 확인하지 못했어요.")
        case .signingIdentityChanged: return L("업데이트 앱의 개발자 서명이 현재 앱과 달라요.")
        case .cannotWrite: return L("앱이 있는 폴더에 쓰기 권한이 없어요. 다운로드 페이지에서 앱을 받아 직접 설치해 주세요.")
        case .parentStillRunning: return L("앱이 종료되지 않아 설치를 취소했어요. 다시 시도해 주세요.")
        case .invalidPlan: return L("업데이트 설치 정보를 확인하지 못했어요.")
        case .restartFailed: return L("새 앱을 시작하지 못해 이전 앱으로 복구했어요.")
        }
    }
}

public enum UpdateArchive {
    public static func sha256Digest(_ value: String?) -> String? {
        guard let value, value.hasPrefix("sha256:") else { return nil }
        let hex = String(value.dropFirst(7)).lowercased()
        guard hex.count == 64, hex.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return hex
    }

    public static func verify(_ file: URL, digest: String?, size: Int64) throws {
        guard let expected = sha256Digest(digest), size > 0, size <= 100 * 1024 * 1024,
              let actual = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber,
              actual.int64Value == size else { throw AppUpdateError.checksumMismatch }
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var hash = SHA256()
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        let result = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard result == expected else { throw AppUpdateError.checksumMismatch }
    }

    /// GitHub computes the digest from whatever was uploaded, so it cannot catch a swapped
    /// release file. The ZIP must also carry an Ed25519 signature from the release key.
    public static func verifySignature(_ file: URL, signature: Data, publicKey: String = signingKey) throws {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        guard let text = String(data: signature, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let raw = Data(base64Encoded: text), raw.count == 64,
              let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              key.isValidSignature(raw, for: data) else { throw AppUpdateError.unsignedUpdate }
    }

    /// Reject links and traversal *before* extraction. Current releases contain no symlinks.
    public static func extract(_ archive: URL, into folder: URL) throws -> URL {
        // Parse raw UTF-8 names. Older macOS unzip/zipinfo sanitize Korean bytes,
        // which cannot be used for trustworthy path validation.
        _ = try entryNames(in: archive)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        _ = try UpdateProcess.output("/usr/bin/ditto", ["-x", "-k", archive.path, folder.path])
        return folder.appendingPathComponent("이걸내가.app")
    }

    public static func entryNames(in archive: URL) throws -> [String] {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        guard data.count >= 22, data.count <= 100 * 1024 * 1024 else { throw AppUpdateError.invalidArchive }
        func u16(_ i: Int) -> Int { Int(data[i]) | Int(data[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        let end = stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1).first {
            u32($0) == 0x06054b50 && $0 + 22 + u16($0 + 20) == data.count
        }
        guard let end, u16(end + 4) == 0, u16(end + 6) == 0,
              u16(end + 8) == u16(end + 10), (1..<10_000).contains(u16(end + 10)) else { throw AppUpdateError.invalidArchive }
        let count = u16(end + 10), start = u32(end + 16)
        guard start + u32(end + 12) == end else { throw AppUpdateError.invalidArchive }
        var offset = start, expanded = 0
        var names: [String] = []
        var unique = Set<String>()
        func validateExtra(_ range: Range<Int>, name: String) throws {
            var i = range.lowerBound
            while i < range.upperBound {
                guard i + 4 <= range.upperBound else { throw AppUpdateError.invalidArchive }
                let kind = u16(i), length = u16(i + 2)
                guard i + 4 + length <= range.upperBound, [0x5855, 0x5455, 0x7875, 0x7075].contains(kind) else { throw AppUpdateError.invalidArchive }
                if kind == 0x7075 {
                    guard length >= 5, String(data: data[(i + 9)..<(i + 4 + length)], encoding: .utf8) == name else { throw AppUpdateError.invalidArchive }
                }
                i += 4 + length
            }
        }
        for _ in 0..<count {
            guard offset + 46 <= end, u32(offset) == 0x02014b50 else { throw AppUpdateError.invalidArchive }
            let length = u16(offset + 28), extra = u16(offset + 30), comment = u16(offset + 32)
            let next = offset + 46 + length + extra + comment
            guard next <= end, u16(offset + 34) == 0, u16(offset + 8) & 1 == 0,
                  [0, 8].contains(u16(offset + 10)), u16(offset + 4) >> 8 == 3,
                  let name = String(data: data[(offset + 46)..<(offset + 46 + length)], encoding: .utf8),
                  isSafeEntry(name), unique.insert(name).inserted else { throw AppUpdateError.invalidArchive }
            let mode = (u32(offset + 38) >> 16) & 0xf000
            guard mode == 0x8000 || mode == 0x4000 else { throw AppUpdateError.invalidArchive }
            expanded += u32(offset + 24)
            guard expanded <= 500 * 1024 * 1024 else { throw AppUpdateError.invalidArchive }
            try validateExtra((offset + 46 + length)..<(offset + 46 + length + extra), name: name)
            let local = u32(offset + 42), compressed = u32(offset + 20)
            guard local + 30 <= start, u32(local) == 0x04034b50 else { throw AppUpdateError.invalidArchive }
            let localName = u16(local + 26), localExtra = u16(local + 28)
            let content = local + 30 + localName + localExtra
            guard content + compressed <= start,
                  u16(local + 6) == u16(offset + 8), u16(local + 8) == u16(offset + 10),
                  data[(local + 30)..<(local + 30 + localName)] == data[(offset + 46)..<(offset + 46 + length)] else { throw AppUpdateError.invalidArchive }
            try validateExtra((local + 30 + localName)..<content, name: name)
            names.append(name)
            offset = next
        }
        guard offset == end else { throw AppUpdateError.invalidArchive }
        return names
    }

    public static func isSafeEntry(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") &&
        !path.split(separator: "/").contains("..") &&
        (path.hasPrefix("이걸내가.app/") || path.hasPrefix("__MACOSX/"))
    }
}

/// Drains output before waiting so subprocesses cannot block on a full pipe.
enum UpdateProcess {
    static func output(_ executable: String, _ arguments: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw AppUpdateError.invalidApp }
        return String(decoding: data, as: UTF8.self)
    }
}
