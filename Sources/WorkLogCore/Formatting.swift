import Foundation

/// 화면과 보고서에서 같이 쓰는 표기. 고른 화면 언어(`Loc.language`)를 따른다.
public enum Fmt {
    public static var locale: Locale { Loc.language.locale }

    public static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        let h = minutes / 60
        let m = minutes % 60
        switch Loc.language {
        case .ko:
            if minutes < 1 { return "1분 미만" }
            if h == 0 { return "\(m)분" }
            return m == 0 ? "\(h)시간" : "\(h)시간 \(m)분"
        case .en:
            if minutes < 1 { return "under 1m" }
            if h == 0 { return "\(m)m" }
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        case .ja:
            if minutes < 1 { return "1分未満" }
            if h == 0 { return "\(m)分" }
            return m == 0 ? "\(h)時間" : "\(h)時間\(m)分"
        }
    }

    public static func number(_ n: Int) -> String {
        n.formatted(.number.locale(locale))
    }

    /// 큰 수를 짧게: 한국어 "123만", 일본어 "123万", 영어 "1.2M"
    public static func compact(_ n: Int) -> String {
        let v = Double(n)
        switch Loc.language {
        case .en:
            if v >= 1_000_000_000 { return String(format: "%.1fB", v / 1_000_000_000) }
            if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
            if v >= 10_000 { return "\(Int((v / 1_000).rounded()))K" }
            return number(n)
        case .ko, .ja:
            let (man, eok) = Loc.language == .ko ? ("만", "억") : ("万", "億")
            if v >= 100_000_000 { return String(format: "%.1f", v / 100_000_000) + eok }
            if v >= 100_000 { return "\(Int((v / 10_000).rounded()))" + man }
            if v >= 10_000 { return String(format: "%.1f", v / 10_000) + man }
            return number(n)
        }
    }

    public static func cost(_ usd: Double) -> String {
        usd >= 100 ? String(format: "$%.0f", usd) : String(format: "$%.2f", usd)
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]

    /// 언어·형식마다 하나씩 만들어 둔다.
    private static func format(_ date: Date, ko: String, en: String, ja: String) -> String {
        let language = Loc.language
        let pattern = language == .ko ? ko : language == .en ? en : ja
        let key = "\(language.rawValue)|\(pattern)"
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let f = formatters[key] { return f.string(from: date) }
        let f = DateFormatter()
        f.locale = language.locale
        f.dateFormat = pattern
        formatters[key] = f
        return f.string(from: date)
    }

    /// 보관함 열쇠로도 쓰니 언어와 상관없이 늘 같은 모양.
    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func day(_ d: Date) -> String { format(d, ko: "M월 d일 (E)", en: "EEE, MMM d", ja: "M月d日 (E)") }
    public static func fullDay(_ d: Date) -> String { format(d, ko: "yyyy년 M월 d일 (E)", en: "EEE, MMM d, yyyy", ja: "yyyy年M月d日 (E)") }
    public static func time(_ d: Date) -> String { format(d, ko: "HH:mm", en: "HH:mm", ja: "HH:mm") }
    public static func dateTime(_ d: Date) -> String { format(d, ko: "M월 d일 HH:mm", en: "MMM d, HH:mm", ja: "M月d日 HH:mm") }
    public static func isoDay(_ d: Date) -> String { isoDayFormatter.string(from: d) }
    public static func shortDay(_ d: Date) -> String { format(d, ko: "M/d", en: "M/d", ja: "M/d") }

    /// "오늘", "어제", "3일 전", 그보다 오래면 날짜.
    public static func relativeDay(_ d: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: d), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case 0: return L("오늘")
        case 1: return L("어제")
        case 2..<7: return L("%@일 전", String(days))
        default: return day(d)
        }
    }

    public static func timeRange(_ a: Date, _ b: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(a, inSameDayAs: b) { return "\(time(a))–\(time(b))" }
        return "\(dateTime(a)) – \(dateTime(b))"
    }

    /// 홈 폴더를 ~ 로 줄인다.
    public static func path(_ p: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    /// 프로젝트 안 파일이면 프로젝트 기준 상대 경로로.
    public static func relativePath(_ p: String, to base: String) -> String {
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return p.hasPrefix(prefix) ? String(p.dropFirst(prefix.count)) : path(p)
    }
}
