import Foundation

/// 줄 단위 JSON 기록 파일(.jsonl)을 메모리 매핑해서 빠르게 훑는다.
enum LineScanner {
    /// `offset` 부터 끝까지, 줄바꿈으로 끝난 완전한 줄마다 `body` 를 부른다.
    /// 아직 쓰는 중인 마지막 줄은 건너뛰고, 다음에 이어 읽을 위치를 돌려준다.
    static func scan(path: String, from offset: Int, body: (UnsafeRawBufferPointer) -> Void) throws -> Int {
        let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped)
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            guard let base = raw.baseAddress, offset < raw.count else { return min(offset, raw.count) }
            var start = offset
            while start < raw.count {
                guard let hit = memchr(base + start, 0x0A, raw.count - start) else { break }
                let end = base.distance(to: UnsafeRawPointer(hit))
                if end > start {
                    body(UnsafeRawBufferPointer(rebasing: raw[start..<end]))
                }
                start = end + 1
            }
            return start
        }
    }

    static func contains(_ line: UnsafeRawBufferPointer, _ needle: StaticString) -> Bool {
        guard let base = line.baseAddress else { return false }
        return needle.withUTF8Buffer { n in
            memmem(base, line.count, n.baseAddress, n.count) != nil
        }
    }

    /// 줄이 이 글자로 시작하는지 (줄 전체를 훑지 않는다).
    static func hasPrefix(_ line: UnsafeRawBufferPointer, _ prefix: StaticString) -> Bool {
        guard let base = line.baseAddress else { return false }
        return prefix.withUTF8Buffer { p in
            p.count <= line.count && memcmp(base, p.baseAddress, p.count) == 0
        }
    }

    static func jsonObject(_ line: UnsafeRawBufferPointer) -> [String: Any]? {
        guard let base = line.baseAddress else { return nil }
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base), count: line.count, deallocator: .none)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// `2026-10-07T04:41:37.347Z` 꼴의 시각을 빠르게 읽는다. ISO8601DateFormatter 보다 훨씬 빠르다.
enum FastDate {
    static func parse(_ s: String) -> Date? {
        var digits: [Int] = []
        digits.reserveCapacity(7)
        var current = 0
        var inNumber = false
        var fraction = 0.0
        var fractionScale = 0.1
        var inFraction = false
        for byte in s.utf8 {
            if byte >= 48 && byte <= 57 {
                let d = Int(byte - 48)
                if inFraction {
                    fraction += Double(d) * fractionScale
                    fractionScale /= 10
                } else {
                    current = current * 10 + d
                    inNumber = true
                }
            } else {
                if inNumber { digits.append(current); current = 0; inNumber = false }
                if byte == 46 /* . */ && digits.count == 6 { inFraction = true } else if inFraction { inFraction = false }
                if byte == 43 /* + */ || (byte == 45 /* - */ && digits.count >= 6) { break }
            }
        }
        if inNumber && !inFraction { digits.append(current) }
        guard digits.count >= 6 else { return nil }
        let days = daysFromCivil(year: digits[0], month: digits[1], day: digits[2])
        let seconds = Double(days * 86_400 + digits[3] * 3_600 + digits[4] * 60 + digits[5]) + fraction
        return Date(timeIntervalSince1970: seconds)
    }

    /// 1970-01-01 부터 며칠째인지 (Howard Hinnant 알고리즘).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}

/// 쉬는 시간을 뺀 실제 작업 시간을 센다.
struct ActiveClock: Codable, Hashable {
    static let idleGap: Double = 10 * 60
    /// 혼자 떨어진 요청 하나도 최소 이만큼은 일한 걸로 친다.
    static let minimumBurst: Double = 60

    var first: Date?
    var last: Date?
    var seconds: Double = 0

    mutating func tick(_ date: Date) {
        guard let prev = last else {
            first = date
            last = date
            seconds = ActiveClock.minimumBurst
            return
        }
        if date < (first ?? date) { first = date }
        guard date > prev else { return }
        let gap = date.timeIntervalSince(prev)
        seconds += gap <= ActiveClock.idleGap ? gap : ActiveClock.minimumBurst
        last = date
    }

    /// 요청 시각(점)과 AI 가 일한 구간을 시간순으로 이어 붙여 잰다. 사이가 10분 안이면 그 틈(답을 읽고 다시 묻는 시간)까지 치고,
    /// 더 벌어지면 쉰 것으로 보고 끊는다. 이어진 덩어리마다 1분을 더한다 (첫 요청을 쓰는 시간).
    /// 구간이 없으면 요청 시각만으로 `tick` 을 차례로 부른 것과 같다.
    static func seconds(points: [Date], spans: [WorkSpan]) -> Double {
        let parts = (points.map { WorkSpan(start: $0, end: $0) } + spans).sorted { $0.start < $1.start }
        var total = 0.0
        var current: WorkSpan?
        for part in parts {
            if var c = current, part.start.timeIntervalSince(c.end) <= idleGap {
                c.end = max(c.end, part.end)
                current = c
            } else {
                if let c = current { total += minimumBurst + c.end.timeIntervalSince(c.start) }
                current = part
            }
        }
        if let c = current { total += minimumBurst + c.end.timeIntervalSince(c.start) }
        return total
    }
}

extension [WorkSpan] {
    /// 기록이 찍힌 시각 하나를 붙인다. 마지막 구간과 10분 안이면 그 구간을 늘리고, 더 벌어졌으면 새 구간을 연다.
    /// 시각이 뒤섞여 앞선 시각이 오면 무시한다.
    mutating func extend(to date: Date) {
        guard let last else {
            append(WorkSpan(start: date, end: date))
            return
        }
        guard date > last.end else { return }
        if date.timeIntervalSince(last.end) <= ActiveClock.idleGap {
            self[count - 1].end = date
        } else {
            append(WorkSpan(start: date, end: date))
        }
    }
}

extension String {
    /// 앞뒤 공백을 지우고 `limit` 자에서 자른다.
    public func clipped(_ limit: Int) -> String {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > limit else { return t }
        return String(t.prefix(limit)) + "…"
    }

    /// 마크다운 기호(굵게, 제목, 목록 기호, 인용)를 걷어 내고 한 줄로. 보고서용.
    public var plainLine: String {
        split(whereSeparator: \.isNewline)
            .map { line -> String in
                var t = line.trimmingCharacters(in: .whitespaces)
                while let first = t.first, "#>-*+".contains(first) { t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
                return t.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            }
            .filter { !$0.isEmpty && !$0.hasPrefix("```") && !$0.allSatisfy { "|-: ".contains($0) } }
            .joined(separator: " ")
    }

    /// AI 답에서 "무엇을 했는지" 한 줄. 마크다운 기호를 걷고, "알겠어요." 같은 앞쪽 짧은 맞장구 문장은 건너뛴다.
    public var outcomeLine: String {
        var text = plainLine.replacingOccurrences(of: "`", with: "")
        while let end = text.range(of: #"[.!?。](\s+|$)"#, options: .regularExpression),
              text.distance(from: text.startIndex, to: end.lowerBound) < 12,
              end.upperBound < text.endIndex {
            text = String(text[end.upperBound...])
        }
        return text
    }

    /// 여러 줄을 한 줄로 합친다. 제목이나 목록용.
    public var singleLine: String {
        split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
