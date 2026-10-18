// 앱 아이콘(Support/AppIcon.icns)을 그린다.  사용: swift scripts/make_icon.swift <출력 폴더>
// 남색 바탕 위에 일지 한 장, 그 위에 도구 색 막대 세 줄과 반짝이.
// 뒤에 scripts/compress_icon.py 로 256색으로 줄여 icns 로 묶는다 (build_app.sh 가 함께 부른다).
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let size: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    // macOS 아이콘 격자: 1024 안에 824 크기 둥근 사각형.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // 단색 남색 바탕. 그라데이션과 바깥 그림자는 256색으로 줄일 때 줄무늬·회색 테두리가 생겨서 뺐다
    // (scripts/compress_icon.py 로 아이콘을 525KB → 50KB 안팎으로 줄인다).
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x22305A).cgColor)
    ctx.fillPath()

    // 일지 종이
    let page = CGRect(x: 262, y: 214, width: 500, height: 600)
    ctx.saveGState()
    ctx.translateBy(x: page.midX, y: page.midY)
    ctx.rotate(by: -0.06)
    ctx.translateBy(x: -page.midX, y: -page.midY)
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.4).cgColor)
    let pagePath = CGPath(roundedRect: page, cornerWidth: 44, cornerHeight: 44, transform: nil)
    ctx.addPath(pagePath)
    ctx.setFillColor(color(0xFBF8F1).cgColor)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // 날짜 머리줄
    ctx.setFillColor(color(0x1B2440, 0.85).cgColor)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 322, y: 700, width: 170, height: 34), cornerWidth: 17, cornerHeight: 17, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(color(0x1B2440, 0.2).cgColor)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 510, y: 700, width: 90, height: 34), cornerWidth: 17, cornerHeight: 17, transform: nil))
    ctx.fillPath()

    // 작업 막대: Codex 파랑, Claude Code 주황, LM Studio 청록
    let bars: [(UInt32, CGFloat, CGFloat)] = [(0xEB6834, 600, 330), (0x2A78D6, 500, 250), (0xEB6834, 400, 290), (0x1BAF7A, 300, 190)]
    for (hex, y, width) in bars {
        ctx.setFillColor(color(0xE6E0D3).cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 322, y: y, width: 380, height: 44), cornerWidth: 22, cornerHeight: 22, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(color(hex).cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 322, y: y, width: width, height: 44), cornerWidth: 22, cornerHeight: 22, transform: nil))
        ctx.fillPath()
    }
    ctx.restoreGState()

    // 반짝이
    func sparkle(center: CGPoint, radius: CGFloat, fill: NSColor) {
        let path = CGMutablePath()
        let waist = radius * 0.22
        path.move(to: CGPoint(x: center.x, y: center.y + radius))
        path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + waist, y: center.y + waist))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: CGPoint(x: center.x + waist, y: center.y - waist))
        path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: CGPoint(x: center.x - waist, y: center.y - waist))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: CGPoint(x: center.x - waist, y: center.y + waist))
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: color(0x000000, 0.3).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(fill.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }
    sparkle(center: CGPoint(x: 742, y: 780), radius: 118, fill: color(0xFFB547))
    sparkle(center: CGPoint(x: 838, y: 640), radius: 50, fill: color(0xFFE2A8))
    return true
}

let iconset = URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: px, height: px)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
print(iconset.path)
