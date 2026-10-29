import AppKit
import SwiftUI
import WorkLogCore

/// 캐릭터 모아를 픽셀 그대로 그린다. 꾸밈 그림이라 VoiceOver 에는 읽히지 않는다 (안내는 옆 글이 한다).
/// 여러 장인 자세는 차례로 넘겨 움직이고, '동작 줄이기'를 켜 두면 첫 장에 멈춘다.
@MainActor
struct MascotView: View {
    var pose: Mascot.Pose
    /// 한 칸의 크기(pt). 2배 화면에서 정수 픽셀이 되게 두어야 칸 크기가 고르다.
    var cell: CGFloat = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let frames = MascotImages.frames[pose] ?? []
        Group {
            if frames.count > 1 && !reduceMotion {
                AnimatedMascot(pose: pose)
            } else if let first = frames.first {
                // 한 칸 = 1픽셀 그림을 보간 없이 늘려 칸 경계가 번지지 않게 한다.
                Image(decorative: first.image, scale: 1)
                    .resizable()
                    .interpolation(.none)
            }
        }
        .frame(width: CGFloat(Mascot.width) * cell, height: CGFloat(Mascot.height) * cell)
        .accessibilityHidden(true)
    }
}

/// 움직이는 모아는 CALayer 의 그림만 바꿔 끼운다. SwiftUI 로 장을 바꾸면 그때마다 한눈에 보기 전체를
/// 다시 배치해 가만히 있어도 CPU 를 10% 가까이 썼고, Canvas 는 CPU 는 줄어도 메모리를 50MB 더 썼다.
private struct AnimatedMascot: NSViewRepresentable {
    var pose: Mascot.Pose

    func makeNSView(context: Context) -> MascotLayerView { MascotLayerView() }
    func updateNSView(_ view: MascotLayerView, context: Context) { view.pose = pose }
}

private final class MascotLayerView: NSView {
    var pose: Mascot.Pose? {
        didSet { if pose != oldValue { restart() } }
    }
    private var index = 0
    private var timer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        layer?.contentsGravity = .resize
    }

    required init?(coder: NSCoder) { nil }

    // 창에서 빠지면 멈추고, 다시 들어오면 처음 장부터.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restart()
    }

    private func restart() {
        timer?.invalidate()
        timer = nil
        index = 0
        show()
    }

    /// 지금 장을 보이고, 그 장에 머무는 시간이 지나면 다음 장으로.
    private func show() {
        guard let pose, let frames = MascotImages.frames[pose], !frames.isEmpty else { return }
        let frame = frames[index % frames.count]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = frame.image
        CATransaction.commit()
        guard window != nil, frames.count > 1 else { return }
        timer = Timer.scheduledTimer(timeInterval: frame.seconds, target: self, selector: #selector(advance), userInfo: nil, repeats: false)
    }

    @objc private func advance() {
        index += 1
        show()
    }
}

/// 자세마다 한 번만 만들어 두는 그림.
@MainActor
private enum MascotImages {
    static let frames: [Mascot.Pose: [(image: CGImage, seconds: Double)]] = Dictionary(uniqueKeysWithValues: Mascot.Pose.allCases.map { pose in
        (pose, Mascot.frames(pose).compactMap { frame in image(frame.rows).map { (image: $0, seconds: frame.seconds) } })
    })

    static func image(_ rows: [String]) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: Mascot.width, height: Mascot.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let hex = Mascot.palette[ch] else { continue }
                ctx.setFillColor(CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                                         blue: CGFloat(hex & 255) / 255, alpha: 1))
                // CGContext 는 아래가 0 이라 줄 순서를 뒤집어 칠한다.
                ctx.fill(CGRect(x: x, y: Mascot.height - 1 - y, width: 1, height: 1))
            }
        }
        return ctx.makeImage()
    }
}
