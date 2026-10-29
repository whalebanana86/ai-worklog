// 캐릭터 모아 그림을 뽑는다. 격자는 Sources/WorkLogCore/Mascot.swift 하나만 써서 앱·터미널과 같은 그림이 나온다.
//   swiftc -O -parse-as-library Sources/WorkLogCore/Mascot.swift scripts/make_mascot.swift -o build.noindex/make_mascot
//   build.noindex/make_mascot docs/brand
// 만드는 것 (배경은 투명, 칸 경계가 번지지 않게 정수 배율):
//   moa.gif        평소 모습 움직임(깜빡임·통통), 한 칸 12px — README 에서 절반 너비로 보여 2배 화면에서도 선명하다
//   moa-poses.png  자세 모음(각 자세의 첫 장), 한 칸 12px — 평소·뿌듯·새 소식·모으는 중·빈손·갸웃·잠
//   moa.png        평소 모습 한 장, 한 칸 10px — 홍보 영상 끝 카드
import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
enum MakeMascot {
    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/brand", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let idle = Mascot.frames(.idle)
        let idleBox = bounds(idle.map(\.rows))
        try writeGIF(idle, box: idleBox, scale: 12, to: out.appendingPathComponent("moa.gif"))
        try writePNG(image(idle[0].rows, box: idleBox, scale: 10), to: out.appendingPathComponent("moa.png"))

        let poses: [Mascot.Pose] = [.idle, .proud, .excited, .gathering, .emptyHanded, .puzzled, .sleeping]
        let firsts = poses.map { Mascot.frames($0)[0].rows }
        let box = bounds(firsts)
        let scale = 12, gap = 4 * scale
        let w = Int(box.width) * scale, h = Int(box.height) * scale
        let sheet = context(width: firsts.count * w + (firsts.count - 1) * gap, height: h)
        for (i, rows) in firsts.enumerated() {
            sheet.draw(image(rows, box: box, scale: scale), in: CGRect(x: i * (w + gap), y: 0, width: w, height: h))
        }
        try writePNG(sheet.makeImage()!, to: out.appendingPathComponent("moa-poses.png"))
        print("만들었어요: \(out.path)/moa.gif, moa-poses.png, moa.png")
    }

    /// 여러 장을 겹쳤을 때 빈 칸이 아닌 곳을 모두 담는 범위 (칸 단위). 장마다 같은 범위로 잘라야 움직여도 자리가 그대로다.
    static func bounds(_ grids: [[String]]) -> CGRect {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for grid in grids {
            for (y, row) in grid.enumerated() {
                for (x, ch) in row.enumerated() where ch != "." {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    static func context(width: Int, height: Int) -> CGContext {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        return ctx
    }

    static func image(_ rows: [String], box: CGRect, scale: Int) -> CGImage {
        let w = Int(box.width), h = Int(box.height)
        let ctx = context(width: w * scale, height: h * scale)
        for (y, row) in rows.enumerated() where y >= Int(box.minY) && y < Int(box.maxY) {
            for (x, ch) in row.enumerated() where x >= Int(box.minX) && x < Int(box.maxX) {
                guard let hex = Mascot.palette[ch] else { continue }
                ctx.setFillColor(CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                                         blue: CGFloat(hex & 255) / 255, alpha: 1))
                // CGContext 는 아래가 0 이라 줄 순서를 뒤집어 칠한다.
                let cx = x - Int(box.minX), cy = h - 1 - (y - Int(box.minY))
                ctx.fill(CGRect(x: cx * scale, y: cy * scale, width: scale, height: scale))
            }
        }
        return ctx.makeImage()!
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: url)
    }

    /// 장마다 머무는 시간을 그대로 담은 GIF (끝없이 되풀이).
    static func writeGIF(_ frames: [Mascot.Frame], box: CGRect, scale: Int, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in frames {
            let delay = [kCGImagePropertyGIFDelayTime: frame.seconds, kCGImagePropertyGIFUnclampedDelayTime: frame.seconds]
            CGImageDestinationAddImage(dest, image(frame.rows, box: box, scale: scale), [kCGImagePropertyGIFDictionary: delay] as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }
}
