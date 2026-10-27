// 广告风格宣传片合成：文字卡片 + 实拍画面（自动对准候选框、缓慢推近），逐帧渲染成 1080p H.264。
// 用法:
//   swift promo/make_promo.swift <输出.mp4> [录屏.mov 候选框记录.tsv]
//   swift promo/make_promo.swift --frames <目录> [录屏.mov 候选框记录.tsv]   只导出几张关键帧 PNG 预览
// 没有录屏时，实拍段落用深灰占位。
import AppKit
import AVFoundation

let W = 1920, H = 1080, FPS: Int32 = 30

// MARK: - 时间线

enum Shot {
    // 文字卡片：lines = [(文字, 字号, 是否渐变)]，dark = 黑底白字
    case card(dur: Double, dark: Bool, lines: [(String, CGFloat, Bool)], mono: String? = nil)
    // 实拍：从录屏第 src 秒开始；裁出这段时间里候选框附近的区域，做成悬浮卡片，push 为起止缩放（缓慢推近）
    case footage(dur: Double, src: Double, push: (CGFloat, CGFloat), caption: String?)
    case end(dur: Double)
}

let timeline: [Shot] = [
    .card(dur: 2.4, dark: true, lines: [("液态玻璃。", 150, true)]),
    .card(dur: 2.4, dark: true, lines: [("现在，来到你的输入法。", 84, false)]),
    .footage(dur: 4.3, src: 7.85, push: (1.0, 1.06), caption: "实时折射，跟随每一次输入。"),
    .card(dur: 2.6, dark: false, lines: [("不是贴图。", 110, false), ("是真正的玻璃。", 110, true)]),
    .footage(dur: 7.0, src: 17.0, push: (1.0, 1.08), caption: "展开，依然通透。"),
    .card(dur: 2.8, dark: true, lines: [("一行命令。", 96, false), ("即刻拥有。", 96, true)], mono: "./install.sh"),
    .end(dur: 4.0),
]

// MARK: - 素材：录屏 + 候选框位置记录（t\tx\ty\tw\th，CG 屏幕坐标）

struct Sample { let t: Double; let r: CGRect }
var samples: [Sample] = []
var asset: AVURLAsset?
var gen: AVAssetImageGenerator?
var screenSize = CGSize(width: 1920, height: 1080)

func loadFootage(_ mov: String, _ log: String) {
    let a = AVURLAsset(url: URL(fileURLWithPath: mov))
    asset = a
    let g = AVAssetImageGenerator(asset: a)
    g.requestedTimeToleranceBefore = .zero
    g.requestedTimeToleranceAfter = .zero
    gen = g
    if let track = a.tracks(withMediaType: .video).first { screenSize = track.naturalSize }
    let text = (try? String(contentsOfFile: log, encoding: .utf8)) ?? ""
    for line in text.split(separator: "\n") {
        let v = line.split(separator: "\t").compactMap { Double($0) }
        if v.count == 5 { samples.append(Sample(t: v[0], r: CGRect(x: v[1], y: v[2], width: v[3], height: v[4]))) }
    }
}

// 录屏比位置记录晚开始约 0.2 秒（screencapture 启动耗时）：录屏时间 = 记录时间 + syncOffset
let syncOffset = 0.2

// 这段时间里候选框出现过的范围，四周留白（上方多留一点，露出正在输入的文字），只拍这一块
func cropRect(src: Double, dur: Double) -> CGRect? {
    let rs = samples.filter { $0.t + syncOffset >= src && $0.t + syncOffset <= src + dur }.map { $0.r }
    guard var u = rs.first else { return nil }
    for r in rs.dropFirst() { u = u.union(r) }
    var c = CGRect(x: u.minX - 140, y: u.minY - 110, width: u.width + 280, height: u.height + 200)
    // 保持 16:7 左右的宽画幅
    let minW = c.height * 16 / 7
    if c.width < minW { c = c.insetBy(dx: (c.width - minW) / 2, dy: 0) }
    c.origin.x = min(max(c.minX, 0), 1920 - c.width)
    c.origin.y = min(max(c.minY, 0), 1080 - c.height)
    return c
}

// MARK: - 绘制工具

func ease(_ x: Double) -> Double { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }

// 片段内透明度：开头 0.45 秒淡入，结尾 0.35 秒淡出
func fade(_ t: Double, _ dur: Double, inT: Double = 0.45, outT: Double = 0.35) -> CGFloat {
    CGFloat(min(ease(t / inT), ease((dur - t) / outT)))
}

let iridescent = [
    NSColor(srgbRed: 0.35, green: 0.62, blue: 1.00, alpha: 1),
    NSColor(srgbRed: 0.62, green: 0.45, blue: 1.00, alpha: 1),
    NSColor(srgbRed: 1.00, green: 0.45, blue: 0.70, alpha: 1),
    NSColor(srgbRed: 1.00, green: 0.70, blue: 0.40, alpha: 1),
]

func font(_ size: CGFloat, mono: Bool = false) -> NSFont {
    mono ? .monospacedSystemFont(ofSize: size, weight: .medium) : .systemFont(ofSize: size, weight: .semibold)
}

// 居中画一行字；gradient=true 时用流光渐变填充（先画成蒙版再填渐变）
func drawText(_ ctx: CGContext, _ s: String, size: CGFloat, centerY: CGFloat, color: NSColor,
              gradient: Bool, alpha: CGFloat, rise: CGFloat, mono: Bool = false, kern: CGFloat = -1) {
    let attr = NSAttributedString(string: s, attributes: [.font: font(size, mono: mono), .foregroundColor: NSColor.white,
                                                          .kern: kern * size / 40])
    let b = attr.size()
    let origin = CGPoint(x: (CGFloat(W) - b.width) / 2, y: centerY - b.height / 2 - rise)
    ctx.saveGState()
    ctx.setAlpha(alpha)
    if gradient {
        let mask = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: mask, flipped: false)
        attr.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: W, height: H), mask: mask.makeImage()!)
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: iridescent.map { $0.cgColor } as CFArray, locations: nil)!
        ctx.drawLinearGradient(g, start: CGPoint(x: origin.x, y: 0), end: CGPoint(x: origin.x + b.width, y: 0), options: [])
    } else {
        let colored = NSMutableAttributedString(attributedString: attr)
        colored.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: colored.length))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        colored.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }
    ctx.restoreGState()
}

// MARK: - 每个镜头的一帧

func renderCard(_ ctx: CGContext, t: Double, dur: Double, dark: Bool, lines: [(String, CGFloat, Bool)], mono: String?) {
    ctx.setFillColor((dark ? NSColor.black : NSColor.white).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let fg = dark ? NSColor.white : NSColor(white: 0.07, alpha: 1)
    let gap: CGFloat = 26
    let totalH = lines.map { $0.1 * 1.25 }.reduce(0, +) + gap * CGFloat(lines.count - 1) + (mono == nil ? 0 : 90)
    var y = CGFloat(H) / 2 + totalH / 2
    for (i, (s, size, grad)) in lines.enumerated() {
        let lineH = size * 1.25
        y -= lineH / 2
        // 多行文字依次出现，每行晚 0.35 秒
        let lt = t - Double(i) * 0.35
        let a = fade(lt, dur - Double(i) * 0.35) * (lt > 0 ? 1 : 0)
        let rise = CGFloat(1 - ease(lt / 0.6)) * -18
        drawText(ctx, s, size: size, centerY: y, color: fg, gradient: grad, alpha: a, rise: rise)
        y -= lineH / 2 + gap
    }
    if let m = mono {
        let lt = t - Double(lines.count) * 0.35
        let a = fade(lt, dur - Double(lines.count) * 0.35) * (lt > 0 ? 1 : 0)
        drawText(ctx, m, size: 44, centerY: y - 30, color: NSColor(white: dark ? 0.75 : 0.3, alpha: 1),
                 gradient: false, alpha: a, rise: 0, mono: true, kern: 0)
    }
}

// 实拍：深色背景上一张悬浮的圆角卡片，卡片里是候选框附近的实拍画面，整体缓慢推近
func renderFootage(_ ctx: CGContext, t: Double, dur: Double, src: Double, push: (CGFloat, CGFloat), caption: String?) {
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor(srgbRed: 0.10, green: 0.10, blue: 0.13, alpha: 1).cgColor, NSColor.black.cgColor] as CFArray,
                        locations: nil)!
    ctx.drawRadialGradient(bg, startCenter: CGPoint(x: W / 2, y: H / 2 + 60), startRadius: 0,
                           endCenter: CGPoint(x: W / 2, y: H / 2 + 60), endRadius: CGFloat(W) * 0.7, options: [.drawsAfterEndLocation])
    let a = fade(t, dur, inT: 0.5, outT: 0.5)
    ctx.saveGState()
    ctx.setAlpha(a)
    if let g = gen, let crop = cropRect(src: src, dur: dur),
       let img = try? g.copyCGImage(at: CMTime(seconds: src + t, preferredTimescale: 600), actualTime: nil) {
        let k = CGFloat(img.width) / 1920   // 录屏像素 / 屏幕点
        let base = min(1500 / crop.width, 640 / crop.height)
        let s = base * (push.0 + (push.1 - push.0) * CGFloat(ease(t / dur)))
        let cw = crop.width * s, ch = crop.height * s
        let card = CGRect(x: (CGFloat(W) - cw) / 2, y: 590 - ch / 2, width: cw, height: ch)
        let path = CGPath(roundedRect: card, cornerWidth: 28, cornerHeight: 28, transform: nil)
        // 卡片投影
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 60, color: NSColor(white: 0, alpha: 0.7).cgColor)
        ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
        ctx.restoreGState()
        if let c = img.cropping(to: CGRect(x: crop.minX * k, y: crop.minY * k, width: crop.width * k, height: crop.height * k)) {
            ctx.saveGState()
            ctx.addPath(path); ctx.clip()
            ctx.interpolationQuality = .high
            ctx.draw(c, in: card)
            ctx.restoreGState()
        }
        // 卡片细边
        ctx.addPath(path); ctx.setStrokeColor(NSColor(white: 1, alpha: 0.12).cgColor); ctx.setLineWidth(1.5); ctx.strokePath()
    } else {
        drawText(ctx, "（实拍画面）", size: 40, centerY: CGFloat(H) / 2, color: .gray, gradient: false, alpha: 1, rise: 0)
    }
    ctx.restoreGState()
    if let cap = caption {
        let ct = t - 0.8
        drawText(ctx, cap, size: 58, centerY: 150, color: .white, gradient: false,
                 alpha: fade(ct, dur - 0.8) * (ct > 0 ? 1 : 0), rise: CGFloat(1 - ease(ct / 0.6)) * -12)
    }
}

func renderEnd(_ ctx: CGContext, t: Double, dur: Double) {
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let a = fade(t, dur, inT: 0.6, outT: 0.6)
    drawText(ctx, "SogouGlass", size: 140, centerY: 620, color: .white, gradient: true, alpha: a,
             rise: CGFloat(1 - ease(t / 0.8)) * -16)
    let t2 = t - 0.5
    let a2 = fade(t2, dur - 0.5, inT: 0.6, outT: 0.6) * (t2 > 0 ? 1 : 0)
    drawText(ctx, "搜狗输入法 · 液态玻璃候选框", size: 46, centerY: 470, color: NSColor(white: 0.85, alpha: 1),
             gradient: false, alpha: a2, rise: 0)
    drawText(ctx, "开源 · 免费 · github.com/zijueyi1/SogouGlass", size: 34, centerY: 380,
             color: NSColor(white: 0.55, alpha: 1), gradient: false, alpha: a2, rise: 0, kern: 0)
}

func renderFrame(_ ctx: CGContext, time: Double) {
    var t0 = 0.0
    for shot in timeline {
        let d: Double
        switch shot { case .card(let x, _, _, _), .footage(let x, _, _, _), .end(let x): d = x }
        if time < t0 + d || t0 + d >= totalDuration {
            let t = time - t0
            switch shot {
            case let .card(dur, dark, lines, mono): renderCard(ctx, t: t, dur: dur, dark: dark, lines: lines, mono: mono)
            case let .footage(dur, src, push, caption): renderFootage(ctx, t: t, dur: dur, src: src, push: push, caption: caption)
            case let .end(dur): renderEnd(ctx, t: t, dur: dur)
            }
            return
        }
        t0 += d
    }
}

let totalDuration = timeline.reduce(0.0) { acc, s in
    switch s { case .card(let d, _, _, _), .footage(let d, _, _, _), .end(let d): return acc + d }
}

func newContext() -> CGContext {
    CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
}

// MARK: - 入口

var args = Array(CommandLine.arguments.dropFirst())
let framesMode = args.first == "--frames"
if framesMode { args.removeFirst() }
guard let out = args.first else { print("用法见文件开头"); exit(1) }
if args.count >= 3 { loadFootage(args[1], args[2]) }

if framesMode {
    try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    var t0 = 0.0
    for (i, shot) in timeline.enumerated() {
        let d: Double
        switch shot { case .card(let x, _, _, _), .footage(let x, _, _, _), .end(let x): d = x }
        let ctx = newContext()
        renderFrame(ctx, time: t0 + d * 0.6)
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/shot\(i).png"))
        t0 += d
    }
    print("frames -> \(out)")
    exit(0)
}

try? FileManager.default.removeItem(atPath: out)
let writer = try! AVAssetWriter(outputURL: URL(fileURLWithPath: out), fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 16_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let frames = Int(totalDuration * Double(FPS))
for f in 0..<frames {
    while !input.isReadyForMoreMediaData { usleep(2000) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    guard let buf = pb else { continue }
    CVPixelBufferLockBaseAddress(buf, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: W, height: H, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    renderFrame(ctx, time: Double(f) / Double(FPS))
    CVPixelBufferUnlockBaseAddress(buf, [])
    adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: FPS))
    if f % 90 == 0 { print("\(f)/\(frames)") }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print("done -> \(out) (\(String(format: "%.1f", totalDuration))s)")
