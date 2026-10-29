import Foundation

/// 이걸내가 캐릭터 '모아': 흩어진 AI 작업 기록을 볼에 모으는 햄스터. 품에 앱 아이콘(말풍선과 체크)을 안고 있다.
/// 칸마다 글자 하나로 그린 픽셀 그림이라 앱 화면·터미널·홍보 그림이 같은 격자를 쓴다.
public enum Mascot {
    public enum Pose: CaseIterable, Sendable {
        /// 모은 기록(말풍선)을 안고 있는 평소 모습 (한눈에 보기 머리).
        case idle
        /// 지난 기간보다 더 일했을 때. 웃는 눈과 반짝임.
        case proud
        /// 새 소식이 있을 때 (새 버전). 눈을 크게 뜨고 머리 위에 느낌표 — 앱 아이콘의 코랄 느낌표.
        case excited
        /// 기록을 모으는 중 (처음 읽을 때). 볼이 부풀었다 줄었다 하는 두 장.
        case gathering
        /// 아직 모은 기록이 없음.
        case emptyHanded
        /// 찾는 기록이 없음 (검색·도구 거르기).
        case puzzled
        /// 쉬는 중 (고른 기간에 기록이 없음).
        case sleeping
    }

    /// 격자 크기 (칸). 모든 자세가 같은 크기라 바꿔 그려도 자리가 흔들리지 않는다.
    public static let width = 30, height = 21

    /// 격자 글자 → 색 (0xRRGGBB). '.' 은 빈 칸.
    public static let palette: [Character: Int] = [
        "O": 0xFF956E,  // 털 (코랄)
        "o": 0xFFC2A8,  // 귀 안쪽·볼 홍조·발
        "C": 0xFFF8E8,  // 배·주둥이 (크림)
        "D": 0xD9694A,  // 테두리·코
        "K": 0x1B1F2E,  // 눈
        "B": 0x3156E8,  // 품에 안은 말풍선
        "X": 0xFF956E,  // 몸 밖 표시 (?, !, Z, 반짝임)
    ]

    /// 그림 한 장과 그 장에 머무는 초.
    public struct Frame: Sendable {
        /// 줄마다 `width` 글자, 모두 `height` 줄.
        public let rows: [String]
        public let seconds: Double
    }

    /// 자세의 그림. 여러 장이면 차례로 넘겨 움직이고 끝나면 처음부터 되풀이한다.
    public static func frames(_ pose: Pose) -> [Frame] {
        switch pose {
        case .idle:
            // 가만히 있다가 눈을 깜빡이고, 조금 뒤 제자리에서 두 번 통통 뛴다.
            let still = canvas(head(eyes: .open) + hugging)
            let blink = canvas(head(eyes: .closed) + hugging)
            return [Frame(rows: still, seconds: 3.2), Frame(rows: blink, seconds: 0.14), Frame(rows: still, seconds: 2.4),
                    Frame(rows: hopped(still), seconds: 0.14), Frame(rows: still, seconds: 0.1), Frame(rows: hopped(still), seconds: 0.14)]
        case .proud:
            // 반짝임이 천천히 켜졌다 꺼지고, 한 바퀴에 한 번 통통 뛴다.
            let bright = canvas(head(eyes: .happy) + hugging, marks: [(3, 1, sparkle), (24, 1, sparkle)])
            let dim = canvas(head(eyes: .happy) + hugging, marks: [(3, 1, twinkle), (24, 1, twinkle)])
            return [Frame(rows: bright, seconds: 0.8), Frame(rows: dim, seconds: 0.8), Frame(rows: bright, seconds: 0.8), Frame(rows: dim, seconds: 0.8),
                    Frame(rows: hopped(bright), seconds: 0.14), Frame(rows: bright, seconds: 0.1), Frame(rows: hopped(bright), seconds: 0.14)]
        case .excited:
            // 통통 두 번 뛰고 잠깐 쉬었다 되풀이.
            let still = canvas(head(eyes: .wide) + hugging, marks: [(25, 1, bang)])
            return [Frame(rows: still, seconds: 1.2), Frame(rows: hopped(still), seconds: 0.14),
                    Frame(rows: still, seconds: 0.1), Frame(rows: hopped(still), seconds: 0.14)]
        case .gathering:
            return [Frame(rows: canvas(head(eyes: .open) + hugging), seconds: 0.45),
                    Frame(rows: canvas(head(eyes: .happy, puffed: true) + hugging), seconds: 0.45)]
        case .emptyHanded:
            return [Frame(rows: canvas(head(eyes: .open) + emptyPaws), seconds: 1)]
        case .puzzled:
            return [Frame(rows: canvas(head(eyes: .open) + emptyPaws, marks: [(24, 0, question)]), seconds: 1)]
        case .sleeping:
            return [Frame(rows: canvas(head(eyes: .closed) + emptyPaws, marks: [(25, 1, sleepZ)]), seconds: 1)]
        }
    }

    /// 터미널용 그림 (자세의 첫 장): 위아래 두 칸을 반쪽 블록(▀▄) 한 글자로 그리고 24비트 색을 입힌다.
    /// 둘레의 빈 칸은 잘라 낸다. 설치 스크립트 끝에 `AIWorkLog cli --moa` 로 보여 준다.
    public static func terminalArt(_ pose: Pose) -> String {
        let grid = frames(pose)[0].rows.map(Array.init)
        let rows = grid.indices.filter { y in grid[y].contains { $0 != "." } }
        let columns = grid.flatMap { row in row.indices.filter { row[$0] != "." } }
        guard let top = rows.first, let bottom = rows.last, let left = columns.min(), let right = columns.max() else { return "" }
        func rgb(_ v: Int) -> String { "\((v >> 16) & 255);\((v >> 8) & 255);\(v & 255)" }
        let reset = "\u{1B}[0m"
        var lines: [String] = []
        for y in stride(from: top, through: bottom, by: 2) {
            var line = ""
            for x in left...right {
                let upper = palette[grid[y][x]]
                let lower = y + 1 <= bottom ? palette[grid[y + 1][x]] : nil
                switch (upper, lower) {
                case (nil, nil): line += " "
                case let (u?, nil): line += "\u{1B}[38;2;\(rgb(u))m▀" + reset
                case let (nil, l?): line += "\u{1B}[38;2;\(rgb(l))m▄" + reset
                case let (u?, l?): line += "\u{1B}[38;2;\(rgb(u));48;2;\(rgb(l))m▀" + reset
                }
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// 한 칸 위로 (통통 뛸 때). 맨 위 줄은 늘 비어 있어 잘리는 것이 없다.
    private static func hopped(_ rows: [String]) -> [String] {
        Array(rows.dropFirst()) + [String(repeating: ".", count: width)]
    }

    // 몸은 테두리 없이 22칸 너비로 그리고, canvas 가 테두리(D)를 둘러 가운데에 놓는다.
    private enum Eyes { case open, wide, happy, closed }

    /// 귀부터 볼까지 9줄. puffed 면 볼이 양옆으로 한 칸씩 부푼다.
    private static func head(eyes: Eyes, puffed: Bool = false) -> [String] {
        let face: [String] = switch eyes {
        case .open, .wide: ["...OOOOKOOOOOOKOOOO...",
                     "..OOOOOKOOOOOOKOOOOO.."]
        case .happy: ["...OOOOKOOOOOOKOOOO...",
                      "..OOOOKOKOOOOKOKOOOO.."]
        case .closed: ["...OOOOOOOOOOOOOOOO...",
                       "..OOOOKKOOOOOOKKOOOO.."]
        }
        let cheeks = puffed
            ? [".OOOOOOOOCDDCOOOOOOOO.",
               "OOOOooOOCCCCCCOOooOOOO",
               "OOOOOOOOOOOOOOOOOOOOOO"]
            : ["..OOOOOOOCDDCOOOOOOO..",
               ".OOOooOOCCCCCCOOooOOO.",
               ".OOOOOOOOOOOOOOOOOOOO."]
        // 크게 뜬 눈은 한 줄 위까지 이어진다.
        let brow = eyes == .wide ? "...OOOOKOOOOOOKOOOO..." : "...OOOOOOOOOOOOOOOO..."
        return [".....OO........OO.....",
                "....OooO......OooO....",
                "....OOOOOOOOOOOOOO....",
                brow] + face + cheeks
    }

    /// 배에 말풍선(체크)을 안은 몸 7줄. 말풍선 꼬리가 아래로 삐져나온다.
    private static let hugging = [
        ".OOOOCCCBBBBBBCCCOOOO.",
        "..OOCCOBBBBBCBBOCCOO..",
        "..OOCCOBBCBCBBBOCCOO..",
        "..OOCCCBBBCBBBBCCCOO..",
        "...OOCCCBBBBBBCCCOO...",
        "....OOOOBOOOOOOOOO....",
        ".....oo........oo.....",
    ]

    /// 아무것도 안 든 몸 7줄. 배에 앞발을 그리면 눈처럼 보여 배가 또 하나의 얼굴이 되니 비워 둔다.
    private static let emptyPaws = [
        ".OOOOCCCCCCCCCCCCOOOO.",
        "..OOCCCCCCCCCCCCCCOO..",
        "..OOCCCCCCCCCCCCCCOO..",
        "..OOCCCCCCCCCCCCCCOO..",
        "...OOCCCCCCCCCCCCOO...",
        "....OOOOOOOOOOOOOO....",
        ".....oo........oo.....",
    ]

    private static let question = [".X.", "X.X", "..X", ".X.", "...", ".X."]
    private static let sleepZ = ["XXXX", "..X.", ".X..", "XXXX"]
    private static let sparkle = [".X.", "XXX", ".X."]
    private static let twinkle = ["...", ".X.", "..."]
    private static let bang = ["X", "X", "X", ".", "X"]

    /// 몸에 테두리를 둘러 격자 가운데(위에서 세 줄 아래)에 놓고, 표시(?, !, Z, 반짝임)를 머리 위 빈 칸에 얹는다.
    private static func canvas(_ body: [String], marks: [(x: Int, y: Int, rows: [String])] = []) -> [String] {
        let cells = body.map(Array.init)
        let h = cells.count, w = cells[0].count
        func filled(_ y: Int, _ x: Int) -> Bool { y >= 0 && y < h && x >= 0 && x < w && cells[y][x] != "." }
        var grid = Array(repeating: Array(repeating: Character("."), count: width), count: height)
        // 테두리 포함 (w+2)×(h+2) 를 왼쪽·오른쪽 여백이 같게 놓는다.
        let left = (width - w - 2) / 2 + 1, top = height - h - 1
        for y in -1...h {
            for x in -1...w {
                if filled(y, x) {
                    grid[top + y][left + x] = cells[y][x]
                } else if filled(y - 1, x) || filled(y + 1, x) || filled(y, x - 1) || filled(y, x + 1) {
                    grid[top + y][left + x] = "D"
                }
            }
        }
        for mark in marks {
            for (dy, row) in mark.rows.enumerated() {
                for (dx, c) in row.enumerated() where c != "." { grid[mark.y + dy][mark.x + dx] = c }
            }
        }
        return grid.map { String($0) }
    }
}
