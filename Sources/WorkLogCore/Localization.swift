import Foundation

/// 화면 언어. 설정에서 고른다.
public enum AppLanguage: String, CaseIterable, Sendable, Identifiable {
    case ko, en, ja

    public var id: String { rawValue }

    /// 고르기 메뉴에 그 언어로 쓰는 이름.
    public var nativeName: String {
        switch self {
        case .ko: return "한국어"
        case .en: return "English"
        case .ja: return "日本語"
        }
    }

    public var locale: Locale {
        switch self {
        case .ko: return Locale(identifier: "ko_KR")
        case .en: return Locale(identifier: "en_US")
        case .ja: return Locale(identifier: "ja_JP")
        }
    }

    /// 설정에 저장된 언어 (앱과 앱 안의 `cli` 가 같이 읽는다).
    public static let defaultsKey = "appLanguage"
    public static var saved: AppLanguage? {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(AppLanguage.init(rawValue:))
    }

    /// 아직 고르지 않았으면 맥의 언어 설정을 따른다.
    public static var system: AppLanguage {
        for language in Locale.preferredLanguages {
            if language.hasPrefix("ko") { return .ko }
            if language.hasPrefix("ja") { return .ja }
            if language.hasPrefix("en") { return .en }
        }
        return .ko
    }
}

/// 화면 글자 번역. 한국어 글을 그대로 열쇠로 쓰고, 영어·일본어는 `Translations` 표에서 찾는다 (없으면 한국어 그대로).
public enum Loc {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: AppLanguage = .ko

    /// 지금 화면 언어. 앱이 시작할 때와 설정에서 바꿀 때 정한다.
    public static var language: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); current = newValue; lock.unlock() }
    }

    static func table(_ language: AppLanguage) -> [String: String] {
        switch language {
        case .ko: return [:]
        case .en: return Translations.en
        case .ja: return Translations.ja
        }
    }

    public static func text(_ key: String, in language: AppLanguage = Loc.language) -> String {
        language == .ko ? key : (table(language)[key] ?? key)
    }

    /// `%@` 자리에 차례로, `%1$@` 자리에 번호대로 넣는다. 언어마다 말 순서가 달라도 된다.
    static func fill(_ format: String, _ args: [String]) -> String {
        guard !args.isEmpty else { return format }
        var out = ""
        var next = 0
        var i = format.startIndex
        while i < format.endIndex {
            let c = format[i]
            guard c == "%" else { out.append(c); i = format.index(after: i); continue }
            var j = format.index(after: i)
            var digits = ""
            while j < format.endIndex, format[j].isNumber { digits.append(format[j]); j = format.index(after: j) }
            if !digits.isEmpty, j < format.endIndex, format[j] == "$" { j = format.index(after: j) } else if !digits.isEmpty { j = format.index(after: i); digits = "" }
            if j < format.endIndex, format[j] == "@" {
                let index = digits.isEmpty ? next : (Int(digits) ?? 1) - 1
                if digits.isEmpty { next += 1 }
                out += args.indices.contains(index) ? args[index] : ""
                i = format.index(after: j)
            } else if j < format.endIndex, format[j] == "%" {
                out.append("%")
                i = format.index(after: j)
            } else {
                out.append(c)
                i = format.index(after: i)
            }
        }
        return out
    }
}

/// 화면에 보이는 글. 한국어 원문을 쓰면 고른 언어로 바꿔 준다. 빈자리는 `%@` (순서를 바꿀 땐 `%1$@`).
///   L("한눈에 보기")  ·  L("요청 %@개", Fmt.number(n))
public func L(_ key: String, _ args: String...) -> String {
    let text = Loc.fill(Loc.text(key), args)
    return Loc.language == .en && !args.isEmpty ? Loc.singularize(text) : text
}

extension Loc {
    /// 영어는 수가 1이면 홑수로: "1 requests" → "1 request".
    static let singulars: [String: String] = [
        "requests": "request", "sessions": "session", "files": "file", "days": "day", "projects": "project",
        "rules": "rule", "skills": "skill", "commands": "command", "subagents": "subagent", "edits": "edit",
        "summaries": "summary", "turns": "turn", "lines": "line", "chars": "char", "folders": "folder", "times": "time",
        "servers": "server", "logs": "log",
    ]

    static func singularize(_ text: String) -> String {
        guard text.contains("1 ") else { return text }
        var out = text
        for (plural, single) in singulars {
            out = out.replacingOccurrences(of: #"(?<![\d.,])1 "# + plural + #"\b"#, with: "1 " + single, options: .regularExpression)
        }
        return out
    }
}
