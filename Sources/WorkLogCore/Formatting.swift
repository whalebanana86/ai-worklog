import Foundation

/// 화면과 보고서에서 같이 쓰는 한국어 표기.
public enum Fmt {
    public static let locale = Locale(identifier: "ko_KR")

    public static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "1분 미만" }
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)분" }
        return m == 0 ? "\(h)시간" : "\(h)시간 \(m)분"
    }

    public static func number(_ n: Int) -> String {
        n.formatted(.number.locale(locale))
    }

    /// 1,234,567 → "123만", 12,345 → "1.2만"
    public static func compact(_ n: Int) -> String {
        let v = Double(n)
        if v >= 100_000_000 { return String(format: "%.1f억", v / 100_000_000) }
        if v >= 100_000 { return "\(Int((v / 10_000).rounded()))만" }
        if v >= 10_000 { return String(format: "%.1f만", v / 10_000) }
        return number(n)
    }

    public static func cost(_ usd: Double) -> String {
        usd >= 100 ? String(format: "$%.0f", usd) : String(format: "$%.2f", usd)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = format
        return f
    }

    private static let dayFormatter = formatter("M월 d일 (E)")
    private static let fullDayFormatter = formatter("yyyy년 M월 d일 (E)")
    private static let timeFormatter = formatter("HH:mm")
    private static let dateTimeFormatter = formatter("M월 d일 HH:mm")
    private static let isoDayFormatter = formatter("yyyy-MM-dd")
    private static let shortDayFormatter = formatter("M/d")

    public static func day(_ d: Date) -> String { dayFormatter.string(from: d) }
    public static func fullDay(_ d: Date) -> String { fullDayFormatter.string(from: d) }
    public static func time(_ d: Date) -> String { timeFormatter.string(from: d) }
    public static func dateTime(_ d: Date) -> String { dateTimeFormatter.string(from: d) }
    public static func isoDay(_ d: Date) -> String { isoDayFormatter.string(from: d) }
    public static func shortDay(_ d: Date) -> String { shortDayFormatter.string(from: d) }

    /// "오늘", "어제", "3일 전", 그보다 오래면 날짜.
    public static func relativeDay(_ d: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: d), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case 0: return "오늘"
        case 1: return "어제"
        case 2..<7: return "\(days)일 전"
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
