import Foundation

/// 기록·설정 파일·AI 답에서 온 글은 믿지 않는다. 그 글을 명령·링크·다른 회사 서버로 보낼 때 거치는 곳 (SECURITY_AUDIT.md).
public enum Safety {
    // MARK: - 링크

    /// 눌러서 열어도 되는 링크: 웹 주소와 메일만.
    /// `file:` 은 앱·스크립트를 실행할 수 있고, `vscode:`·`smb:` 같은 앱 전용 주소도 다른 프로그램을 움직인다.
    public static func isSafeLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "http", "https": return url.host?.isEmpty == false
        case "mailto": return true
        default: return false
        }
    }

    /// 마크다운에서 온 링크 중 열면 안 되는 것은 링크만 떼고 글자는 남긴다.
    public static func removingUnsafeLinks(_ text: AttributedString) -> AttributedString {
        var unsafe: [Range<AttributedString.Index>] = []
        for (link, range) in text.runs[\.link] {
            if let link, !isSafeLink(link) { unsafe.append(range) }
        }
        var out = text
        for range in unsafe { out[range].link = nil }
        return out
    }

    // MARK: - 실행 파일 찾기

    /// PATH 에서 절대 경로만 남긴다. 상대 경로(`node_modules/.bin`, `.`)는 지금 폴더 기준이라 저장소 안의 가짜 프로그램이 잡힐 수 있다.
    public static func absolutePaths(in path: String) -> [String] {
        path.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
    }

    // MARK: - 셸 명령에 넣는 값

    /// 세션 ID 로 쓸 수 있는 글: 영문·숫자로 시작하고 영문·숫자·`-`·`_`·`.` 만 (Claude·Codex 의 ID 는 UUID 꼴이다).
    /// 셸 문법이나 `--옵션`처럼 보이는 ID 는 명령에 넣지 않는다.
    public static func isPlainIdentifier(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first, s.unicodeScalars.count <= 128,
              CharacterSet.alphanumerics.contains(first), first.isASCII else { return false }
        return s.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)) }
    }

    // MARK: - 비밀값 가리기

    public static let redacted = "[REDACTED]"

    /// 흔한 키·토큰 꼴. 오탐을 줄이려고 앞머리가 분명한 것만 찾는다.
    private static let secretPatterns: [NSRegularExpression] = [
        #"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?(-----END [A-Z0-9 ]*PRIVATE KEY-----|$)"#,
        #"\bsk-[A-Za-z0-9_\-]{20,}"#,                       // Anthropic·OpenAI
        #"\bgh[pousr]_[A-Za-z0-9]{30,}"#,                   // GitHub
        #"\bgithub_pat_[A-Za-z0-9_]{30,}"#,
        #"\bxox[abposr]-[A-Za-z0-9\-]{10,}"#,               // Slack
        #"\b(AKIA|ASIA)[0-9A-Z]{16}\b"#,                    // AWS 액세스 키
        #"\bAIza[0-9A-Za-z_\-]{35}"#,                        // Google API 키
        #"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"#, // JWT
        #"(?i)\bBearer\s+[A-Za-z0-9._~+/=\-]{20,}"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// 글 속 키·토큰을 `[REDACTED]` 로 바꾼다. 요약 재료(다른 회사 서버로 간다)와 화면·터미널에 보이는 오류 글에 쓴다.
    public static func redactingSecrets(_ text: String) -> String {
        var out = text
        for pattern in secretPatterns {
            out = pattern.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: redacted)
        }
        return out
    }
}
