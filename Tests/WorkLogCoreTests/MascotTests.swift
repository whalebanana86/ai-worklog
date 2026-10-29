import XCTest
@testable import WorkLogCore

/// 캐릭터 모아 격자: 크기가 어긋나거나 모르는 글자가 섞이면 그림이 틀어진다.
final class MascotTests: XCTestCase {
    func testEveryPoseFillsTheSameGridWithKnownColors() {
        for pose in Mascot.Pose.allCases {
            for frame in Mascot.frames(pose) {
                XCTAssertEqual(frame.rows.count, 21, "\(pose)")
                XCTAssertGreaterThan(frame.seconds, 0, "\(pose)")
                for row in frame.rows {
                    XCTAssertEqual(row.count, 30, "\(pose): \(row)")
                    XCTAssertTrue(row.allSatisfy { $0 == "." || Mascot.palette[$0] != nil }, "\(pose): \(row)")
                }
            }
        }
    }

    /// 빈 화면 카드의 모아는 가만히 있고, 한눈에 보기·업데이트 창·첫 읽기의 모아만 움직인다.
    func testWhichPosesMove() {
        XCTAssertEqual(Mascot.frames(.idle).count, 6)
        XCTAssertEqual(Mascot.frames(.proud).count, 7)
        XCTAssertEqual(Mascot.frames(.excited).count, 4)
        XCTAssertEqual(Mascot.frames(.gathering).count, 2)
        XCTAssertEqual(Mascot.frames(.emptyHanded).count, 1)
        XCTAssertEqual(Mascot.frames(.puzzled).count, 1)
        XCTAssertEqual(Mascot.frames(.sleeping).count, 1)
    }

    /// 통통 뛰는 장은 가만히 있는 장을 한 칸 위로 올린 것이다. 뛰는 자세는 맨 위 줄이 비어 있어 표시(!, 반짝임)가 잘리지 않는다.
    func testHopMovesUpOneRow() {
        let idle = Mascot.frames(.idle)
        XCTAssertEqual(Array(idle[3].rows.prefix(20)), Array(idle[0].rows.dropFirst()))
        XCTAssertEqual(idle[3].rows[20], String(repeating: ".", count: 30))
        for pose in [Mascot.Pose.idle, .proud, .excited] {
            XCTAssertEqual(Mascot.frames(pose)[0].rows[0], String(repeating: ".", count: 30), "\(pose)")
        }
    }

    /// 터미널 그림: 빈 둘레를 잘라 두 칸을 한 글자로. 뿌듯은 반짝임까지 가로 24칸, 세로 20칸 → 10줄.
    func testTerminalArtIsTrimmedHalfBlocks() {
        let lines = Mascot.terminalArt(.proud).split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 10)
        for line in lines {
            let visible = line.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
            XCTAssertEqual(visible.count, 24)
        }
    }

    /// 물음표는 몸 바깥 빈 칸에만 얹힌다: 빈손과 다른 칸은 모두 빈 칸 → 표시(X) 뿐이다.
    func testQuestionMarkStaysOutsideTheBody() {
        let puzzled = Mascot.frames(.puzzled)[0].rows.map(Array.init)
        let empty = Mascot.frames(.emptyHanded)[0].rows.map(Array.init)
        var marks = 0
        for y in 0..<21 {
            for x in 0..<30 where puzzled[y][x] != empty[y][x] {
                XCTAssertEqual(empty[y][x], ".")
                XCTAssertEqual(puzzled[y][x], "X")
                marks += 1
            }
        }
        XCTAssertEqual(marks, 6)
    }

    /// 몸은 좌우 여백이 같아 격자 가운데에 놓인다 (볼이 부푼 장도). 표시가 없는 자세로 본다.
    func testBodyIsCentered() {
        for frame in Mascot.frames(.emptyHanded) + Mascot.frames(.gathering) {
            let used = frame.rows.map(Array.init).flatMap { row in row.indices.filter { row[$0] != "." } }
            XCTAssertEqual(used.min()! + used.max()!, 29)
        }
    }
}
