// 앱 아이콘(Support/AppIcon.icns)을 그린다.  사용: swift scripts/make_icon.swift <출력 폴더>
// 파란 바탕, 크림색 말풍선, 완료 체크와 작은 놀람 표시.
// 뒤에 scripts/compress_icon.py 로 256색으로 줄여 icns 로 묶는다 (build_app.sh 가 함께 부른다).
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let size: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// 이걸내가: a speech bubble ("I did that?") with a confident completion mark.
// Broad solid shapes stay readable in the Dock and at 16px; no lettering or AI sparkles.
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    func roundRect(_ rect: CGRect, radius: CGFloat, fill: UInt32) {
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(color(fill).cgColor)
        ctx.fillPath()
    }

    // Standard macOS icon inset, with a saturated blue tile.
    roundRect(CGRect(x: 100, y: 100, width: 824, height: 824), radius: 186, fill: 0x3156E8)

    // A warm paper speech bubble. The tail points back toward the person doing the work.
    roundRect(CGRect(x: 232, y: 310, width: 560, height: 430), radius: 106, fill: 0xFFF8E8)
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: 325, y: 345))
    tail.addLine(to: CGPoint(x: 325, y: 219))
    tail.addQuadCurve(to: CGPoint(x: 355, y: 221), control: CGPoint(x: 325, y: 195))
    tail.addLine(to: CGPoint(x: 492, y: 335))
    tail.closeSubpath()
    ctx.addPath(tail)
    ctx.setFillColor(color(0xFFF8E8).cgColor)
    ctx.fillPath()

    // "I did it": a large, open check that survives small icon sizes.
    let check = CGMutablePath()
    check.move(to: CGPoint(x: 371, y: 523))
    check.addLine(to: CGPoint(x: 466, y: 428))
    check.addLine(to: CGPoint(x: 645, y: 613))
    ctx.addPath(check)
    ctx.setStrokeColor(color(0x2549D6).cgColor)
    ctx.setLineWidth(66)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    // The small orange surprise badge is deliberately secondary to the check.
    ctx.setFillColor(color(0xFF956E).cgColor)
    ctx.fillEllipse(in: CGRect(x: 671, y: 652, width: 160, height: 160))
    roundRect(CGRect(x: 738, y: 720, width: 26, height: 57), radius: 13, fill: 0x243B83)
    ctx.setFillColor(color(0x243B83).cgColor)
    ctx.fillEllipse(in: CGRect(x: 738, y: 684, width: 26, height: 26))
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
