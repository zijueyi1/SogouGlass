// 玻璃样品墙：在屏幕上排出多块不同参数的 NSGlassEffectView，供截图对比
// 用法: gallery <秒数> <样品>...   样品格式 "v=3,a=0,s=0,u=0,o=0.8,st=clear"
import AppKit

let seconds = Double(CommandLine.arguments[1]) ?? 8
let specs = Array(CommandLine.arguments.dropFirst(2))

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main!.frame
let env = ProcessInfo.processInfo.environment
let cols = Int(env["COLS"] ?? "4") ?? 4
let pillW = CGFloat(Double(env["PILL_W"] ?? "260") ?? 260), pillH = CGFloat(Double(env["PILL_H"] ?? "44") ?? 44)
let gapX: CGFloat = 24, gapY: CGFloat = 34
var panels: [NSPanel] = []
let rows = (specs.count + cols - 1) / cols
let w = CGFloat(cols) * (pillW + gapX) + gapX, h = CGFloat(rows) * (pillH + gapY) + gapY
// 环境变量 ORIGIN="x,y"（AppKit 坐标，左下原点）可指定样品墙位置，默认居中
let origin = ProcessInfo.processInfo.environment["ORIGIN"]?.split(separator: ",").compactMap { Double($0) }
let ox = origin?.count == 2 ? CGFloat(origin![0]) : screen.midX - w / 2
let oy = origin?.count == 2 ? CGFloat(origin![1]) : screen.midY - h / 2
let win = NSWindow(contentRect: CGRect(x: ox, y: oy, width: w, height: h),
                   styleMask: .borderless, backing: .buffered, defer: false)
win.isOpaque = false; win.backgroundColor = .clear; win.level = .statusBar; win.ignoresMouseEvents = true
let root = NSView(frame: CGRect(x: 0, y: 0, width: w, height: h)); win.contentView = root

// 可选背景：环境变量 BACKDROP 指定一张图，垫在样品下面一层，再叠几行黑字，方便看透明度和折射
if let bd = ProcessInfo.processInfo.environment["BACKDROP"], let img = NSImage(contentsOfFile: bd) {
    let back = NSWindow(contentRect: win.frame, styleMask: .borderless, backing: .buffered, defer: false)
    back.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1); back.ignoresMouseEvents = true
    let iv = NSImageView(frame: CGRect(x: 0, y: 0, width: w, height: h))
    iv.image = img; iv.imageScaling = .scaleAxesIndependently
    back.contentView = iv
    for y in stride(from: CGFloat(8), to: h, by: 26) {
        let t = NSTextField(labelWithString: String(repeating: "The quick brown fox 敏捷的棕色狐狸 1234567890  ", count: 4))
        t.font = .systemFont(ofSize: 14, weight: .semibold); t.textColor = NSColor(white: 0, alpha: 0.8)
        t.frame = CGRect(x: 0, y: y, width: w, height: 18); iv.addSubview(t)
    }
    back.orderFrontRegardless()
}

let font = NSFont(name: "PingFangSC-Regular", size: 16)!
for (i, spec) in specs.enumerated() {
    var kv: [String: String] = [:]
    spec.split(separator: ",").forEach { let p = $0.split(separator: "="); if p.count == 2 { kv[String(p[0])] = String(p[1]) } }
    let col = i % cols, row = i / cols
    let frame = CGRect(x: gapX + CGFloat(col) * (pillW + gapX), y: h - gapY - CGFloat(row + 1) * (pillH + gapY) + gapY / 2, width: pillW, height: pillH)
    // 每块样品一个独立窗口，和 SogouGlass 的结构一致（玻璃窗口 + 窗口阴影）
    let screenFrame = CGRect(x: ox + frame.minX, y: oy + frame.minY, width: frame.width, height: frame.height)
    let pw = NSPanel(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    pw.isOpaque = false; pw.backgroundColor = .clear; pw.ignoresMouseEvents = true
    pw.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    pw.hasShadow = (kv["sh"] ?? "1") == "1"
    let g = NSGlassEffectView()
    g.style = kv["st"] == "regular" ? .regular : .clear
    if let rs = kv["r"] { g.cornerRadius = rs == "cap" ? pillH / 2 : CGFloat(Double(rs) ?? 13) } else { g.cornerRadius = 13 }
    if let v = kv["v"].flatMap(Int.init) { g.setValue(v, forKey: "_variant") }
    if let a = kv["a"].flatMap(Int.init) { g.setValue(a, forKey: "_adaptiveAppearance") }
    if let s = kv["s"].flatMap(Int.init) { g.setValue(s, forKey: "_scrimState") }
    if let u = kv["u"].flatMap(Int.init) { g.setValue(u, forKey: "_subduedState") }
    if let l = kv["l"].flatMap(Int.init) { g.setValue(l, forKey: "_contentLensing") }
    if kv["i"] == "1" { g.effectIsInteractive = true }
    if kv["rs"] == "1" { g.setValue(true, forKey: "_useReducedShadowRadius") }
    if let o = kv["o"].flatMap(Double.init) { g.alphaValue = o }
    // 着色: t=w0.08 白色 / t=k0.05 黑色
    if let t = kv["t"], let a = Double(t.dropFirst()) { g.tintColor = NSColor(white: t.hasPrefix("w") ? 1 : 0, alpha: a) }
    pw.contentView = g
    // 模拟搜狗文字：首选蓝色，其他正文色；halo=1 加白色光晕（当前皮肤的做法）
    let line = NSMutableAttributedString()
    let shadow = NSShadow(); shadow.shadowColor = NSColor(white: 1, alpha: 0.85); shadow.shadowBlurRadius = 3
    let weight: NSFont.Weight = kv["fw"] == "m" ? .medium : .regular
    let f = NSFont.systemFont(ofSize: 16, weight: weight)
    for (k, wd) in ["液态", "玻璃", "晶莹", "剔透", "高级"].enumerated() {
        var attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: k == 0 ? NSColor.systemBlue : NSColor.labelColor]
        if kv["halo"] == "1" { attrs[.shadow] = shadow }
        line.append(NSAttributedString(string: "\(k + 1).\(wd)   ", attributes: attrs))
    }
    let text = NSTextField(labelWithAttributedString: line)
    text.frame = CGRect(x: CGFloat(Double(kv["px"] ?? "12") ?? 12), y: (pillH - 22) / 2, width: pillW - 20, height: 22)
    // 玻璃形状会贴合 contentView，所以用铺满的容器包住文字
    let box = NSView(frame: CGRect(x: 0, y: 0, width: pillW, height: pillH)); box.autoresizingMask = [.width, .height]
    box.addSubview(text)
    g.contentView = box
    pw.orderFrontRegardless()
    panels.append(pw)
    let label = NSTextField(labelWithString: spec)
    label.font = .monospacedSystemFont(ofSize: 11, weight: .bold); label.textColor = .white
    label.backgroundColor = NSColor(white: 0, alpha: 0.6); label.drawsBackground = true
    label.frame = CGRect(x: frame.minX, y: frame.maxY + 2, width: pillW, height: 14)
    root.addSubview(label)
}
win.orderFrontRegardless()
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
app.run()
