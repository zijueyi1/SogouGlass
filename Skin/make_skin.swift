// 生成搜狗输入法 Mac 版「液态玻璃」皮肤贴图
// 用法: swift make_skin.swift <输出目录>
import AppKit

struct Theme {
    let dark: Bool
    // 晶莹剔透：中间几乎全透明，质感交给边缘
    var fillTop: NSColor { dark ? NSColor(white: 0.08, alpha: 0.14) : NSColor(white: 1.0, alpha: 0.10) }
    var fillBottom: NSColor { dark ? NSColor(white: 0.04, alpha: 0.18) : NSColor(white: 1.0, alpha: 0.05) }
    var hairline: NSColor { dark ? NSColor(white: 0, alpha: 0.45) : NSColor(white: 0, alpha: 0.13) }
    var rim: CGFloat { dark ? 0.75 : 1.0 }
    var accent: NSColor { dark ? NSColor(srgbRed: 10/255, green: 132/255, blue: 1, alpha: 1)
                               : NSColor(srgbRed: 0, green: 122/255, blue: 1, alpha: 1) }
    var text: NSColor { dark ? NSColor(white: 1, alpha: 0.92) : NSColor(srgbRed: 29/255, green: 29/255, blue: 31/255, alpha: 0.92) }
}

func render(_ w: Int, _ h: Int, _ scale: Int, _ draw: (CGRect) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w * scale, pixelsHigh: h * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func rounded(_ r: CGRect, _ inset: CGFloat, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r.insetBy(dx: inset, dy: inset), xRadius: max(radius - inset, 0), yRadius: max(radius - inset, 0))
}

// 液态玻璃（仿 macOS 27 Dock）：近乎透明的底 + 内侧折射光带 + 明亮镜面边缘 + 左上/右下角的光斑
// 所有边缘效果都控制在 5px 内，落在九宫格的不拉伸区域里
func drawGlass(_ r: CGRect, radius: CGFloat, _ t: Theme) {
    let outer = rounded(r, 0, radius)
    NSGradient(starting: t.fillBottom, ending: t.fillTop)!.draw(in: outer, angle: 90)

    NSGraphicsContext.saveGraphicsState()
    outer.addClip()

    // 内侧折射光带：从边缘往里逐渐消失，做出玻璃的厚度
    for i in 0..<5 {
        let k = 1 - CGFloat(i) / 5
        NSColor(white: 1, alpha: 0.10 * k * k * t.rim).setStroke()
        let p = rounded(r, 1.5 + CGFloat(i), radius); p.lineWidth = 1; p.stroke()
    }
    // 下沿内侧一道暗带，模拟光线穿过玻璃底部的折射
    NSGradient(colors: [NSColor(white: 0, alpha: t.dark ? 0.18 : 0.06), NSColor(white: 0, alpha: 0)])!
        .draw(in: CGRect(x: r.minX, y: r.minY, width: r.width, height: 6), angle: 90)

    // 镜面边缘：整圈有一道亮边，上沿和下沿最亮
    let rimShape = NSBezierPath(cgPath: rounded(r, 0.9, radius).cgPath
        .copy(strokingWithWidth: 1.2, lineCap: .round, lineJoin: .round, miterLimit: 1))
    NSGraphicsContext.saveGraphicsState()
    rimShape.addClip()
    NSGradient(colors: [NSColor(white: 1, alpha: 0.75 * t.rim), NSColor(white: 1, alpha: 0.30 * t.rim),
                        NSColor(white: 1, alpha: 0.30 * t.rim), NSColor(white: 1, alpha: 0.95 * t.rim)],
               atLocations: [0, 0.35, 0.65, 1], colorSpace: .deviceRGB)!.draw(in: r, angle: 90)
    // 左上、右下角的高光斑
    for (c, a) in [(CGPoint(x: r.minX + radius * 0.6, y: r.maxY - radius * 0.4), 1.0),
                   (CGPoint(x: r.maxX - radius * 0.6, y: r.minY + radius * 0.4), 0.7)] {
        NSGradient(colors: [NSColor(white: 1, alpha: a * t.rim), NSColor(white: 1, alpha: 0)])!
            .draw(fromCenter: c, radius: 0, toCenter: c, radius: radius * 1.1, options: [])
    }
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()

    // 外侧细线：浅色背景上勾出轮廓
    t.hairline.setStroke()
    let line = rounded(r, 0.25, radius); line.lineWidth = 0.5; line.stroke()
}

func chevron(_ r: CGRect, up: Bool, color: NSColor) {
    let p = NSBezierPath()
    let cx = r.midX, cy = r.midY, dx: CGFloat = 4, dy: CGFloat = 2.2
    if up {
        p.move(to: NSPoint(x: cx - dx, y: cy - dy)); p.line(to: NSPoint(x: cx, y: cy + dy)); p.line(to: NSPoint(x: cx + dx, y: cy - dy))
    } else {
        p.move(to: NSPoint(x: cx - dx, y: cy + dy)); p.line(to: NSPoint(x: cx, y: cy - dy)); p.line(to: NSPoint(x: cx + dx, y: cy + dy))
    }
    p.lineWidth = 1.7; p.lineCapStyle = .round; p.lineJoinStyle = .round
    color.setStroke(); p.stroke()
}

func preview(_ t: Theme) -> Data {
    render(181, 60, 2) { b in
        let bg = t.dark ? [NSColor(srgbRed: 0.10, green: 0.12, blue: 0.22, alpha: 1), NSColor(srgbRed: 0.35, green: 0.16, blue: 0.30, alpha: 1)]
                        : [NSColor(srgbRed: 0.98, green: 0.62, blue: 0.30, alpha: 1), NSColor(srgbRed: 0.45, green: 0.62, blue: 0.95, alpha: 1)]
        NSGradient(colors: bg)!.draw(in: b, angle: -20)
        NSColor(white: 1, alpha: t.dark ? 0.10 : 0.45).setFill()
        NSBezierPath(ovalIn: CGRect(x: 110, y: -20, width: 90, height: 70)).fill()
        NSColor(srgbRed: 0.75, green: 0.25, blue: 0.20, alpha: t.dark ? 0.35 : 0.55).setFill()
        NSBezierPath(rect: CGRect(x: 55, y: 0, width: 14, height: 60)).fill()
        let bar = CGRect(x: 12, y: 13, width: 157, height: 34)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow(); sh.shadowColor = NSColor(white: 0, alpha: 0.18); sh.shadowBlurRadius = 8; sh.shadowOffset = NSSize(width: 0, height: -3); sh.set()
        NSColor(white: 1, alpha: 0.01).setFill(); NSBezierPath(roundedRect: bar, xRadius: 13, yRadius: 13).fill()
        NSGraphicsContext.restoreGraphicsState()
        drawGlass(bar, radius: 13, t)
        let font = NSFont(name: "PingFangSC-Regular", size: 15) ?? .systemFont(ofSize: 15)
        var x: CGFloat = 24
        for (i, s) in ["液", "态", "玻", "璃"].enumerated() {
            let numColor = i == 0 ? t.accent : t.text.withAlphaComponent(0.45)
            let str = NSMutableAttributedString(string: "\(i + 1)", attributes: [.font: font, .foregroundColor: numColor])
            str.append(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: i == 0 ? t.accent : t.text]))
            str.draw(at: NSPoint(x: x, y: 20)); x += 32
        }
        chevron(CGRect(x: 150, y: 30, width: 12, height: 10), up: true, color: t.text.withAlphaComponent(0.25))
        chevron(CGRect(x: 150, y: 20, width: 12, height: 10), up: false, color: t.accent)
    }
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let overlay = CommandLine.arguments.dropFirst(2).contains("overlay")
func write(_ d: Data, _ path: String) {
    let u = out.appendingPathComponent(path)
    try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! d.write(to: u)
}

for t in [Theme(dark: false), Theme(dark: true)] {
    let dir = t.dark ? "SkinDark" : "Skin"
    for (scale, suffix) in [(1, ""), (2, "@2x")] {
        // 主体 52x32，九宫格中心区 (15,13,23,6)，圆角 13 刚好落在拉伸区外
        // overlay 模式：底板全透明，由 SogouGlass 在下面垫原生液态玻璃
        let trunk = render(52, 32, scale) { b in
            if overlay { NSColor(white: 1, alpha: 0.004).setFill(); b.fill() } else { drawGlass(b, radius: 13, t) }
        }
        write(trunk, "\(dir)/skin\(suffix).png"); write(trunk, "\(dir)/skin_10\(suffix).png")
        // 去掉右下角搜狗水印
        let empty = render(32, 30, scale) { _ in }
        write(empty, "\(dir)/chars_0\(suffix).png"); write(empty, "\(dir)/chars_0_10\(suffix).png")
        for state in 0...3 {
            let c = state == 3 ? t.text.withAlphaComponent(0.25) : (state == 2 ? t.accent.blended(withFraction: 0.25, of: .black)! : t.accent)
            write(render(13, 11, scale) { b in chevron(b, up: true, color: c) }, "\(dir)/pageup_\(state)\(suffix).png")
            write(render(13, 11, scale) { b in chevron(b, up: false, color: c) }, "\(dir)/pagedown_\(state)\(suffix).png")
        }
    }
    let p = preview(t)
    write(p, t.dark ? "singleImage_dark.png" : "singleImage.png")
    write(p, t.dark ? "doubleLineImage_dark.png" : "doubleLineImage.png")
}
print("done ->", out.path)
