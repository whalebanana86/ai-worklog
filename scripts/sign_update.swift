// 앱 안 업데이트용 zip 에 배포 서명(Ed25519)을 붙인다. 설치된 앱은 이 서명이 맞는 zip 만 설치한다.
//   UPDATE_SIGNING_KEY=<비밀키> swift scripts/sign_update.swift <zip>   → <zip>.sig (package_release.sh 가 부른다)
//   swift scripts/sign_update.swift --new-key <파일>                    새 키: 비밀키는 그 파일(600)에만 쓰고 공개키만 출력
// 비밀키는 GitHub Secrets 의 UPDATE_SIGNING_KEY 에, 공개키는 Sources/WorkLogCore/UpdateSigningKey.swift 에 넣는다.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
let fm = FileManager.default

if args.count == 2, args[0] == "--new-key" {
    let file = URL(fileURLWithPath: args[1])
    guard !fm.fileExists(atPath: file.path) else { fail("이미 있어요: \(file.path) (덮어쓰지 않아요)") }
    try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let key = Curve25519.Signing.PrivateKey()
    guard fm.createFile(atPath: file.path, contents: Data(key.rawRepresentation.base64EncodedString().utf8),
                        attributes: [.posixPermissions: 0o600]) else { fail("비밀키를 쓰지 못했어요: \(file.path)") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
    exit(0)
}

guard args.count == 1 else { fail("사용: UPDATE_SIGNING_KEY=<비밀키> swift scripts/sign_update.swift <zip>") }
guard let secret = ProcessInfo.processInfo.environment["UPDATE_SIGNING_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      let raw = Data(base64Encoded: secret), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
else { fail("UPDATE_SIGNING_KEY 가 없거나 올바르지 않아요.") }
// 앱에 넣은 공개키와 짝인지 먼저 본다. 짝이 아닌 키로 서명하면 설치된 앱이 그 업데이트를 거부한다.
let keyFile = "Sources/WorkLogCore/UpdateSigningKey.swift"
let source = (try? String(contentsOfFile: keyFile, encoding: .utf8)) ?? ""
guard source.contains("\"\(key.publicKey.rawRepresentation.base64EncodedString())\"") else {
    fail("UPDATE_SIGNING_KEY 가 \(keyFile) 의 공개키와 짝이 아니에요.")
}
let zip = URL(fileURLWithPath: args[0])
guard let data = try? Data(contentsOf: zip) else { fail("zip 을 읽지 못했어요: \(zip.path)") }
let signature = try key.signature(for: data)
guard key.publicKey.isValidSignature(signature, for: data) else { fail("만든 서명이 확인되지 않아요.") }
try (signature.base64EncodedString() + "\n").write(to: zip.appendingPathExtension("sig"), atomically: true, encoding: .utf8)
print("서명했어요: \(zip.lastPathComponent).sig")
