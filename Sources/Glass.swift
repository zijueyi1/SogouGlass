// 玻璃跟随：找到搜狗输入法的弹出窗口，在它正下方一层放一块系统原生的液态玻璃（NSGlassEffectView）并实时跟随。
// 搜狗那边用全透明皮肤，只负责显示文字。
// 调参（改完一秒内生效）：
//   defaults write com.zijue.sogouglass style -string clear|regular
//   defaults write com.zijue.sogouglass cornerRadius -float 0      (<=0 胶囊形，圆角不超过 maxRadius)
//   defaults write com.zijue.sogouglass maxRadius -float 20
//   defaults write com.zijue.sogouglass insetX -float -6           (负数=玻璃比候选框宽出多少)
//   defaults write com.zijue.sogouglass insetY -float -3
//   defaults write com.zijue.sogouglass tint -string "1,1,1,0.0"   (r,g,b,a 着色)
//   defaults write com.zijue.sogouglass variant -int 11            (内部玻璃变体 0-40，11 = 透镜玻璃)
//   defaults write com.zijue.sogouglass adaptive -int 0            (0-2，随背景调整外观)
//   defaults write com.zijue.sogouglass scrim -int 0 / subdued -int 0
//   defaults write com.zijue.sogouglass opacity -float 0.8         (玻璃整体不透明度)
//   defaults write com.zijue.sogouglass shadowOpacity -float 0.12  (外投影，0 关闭)
//   defaults write com.zijue.sogouglass shadowRadius -float 10
// 内部属性改回默认需要重启本程序
import AppKit

// 以 App 包运行时 standard 即 com.zijue.sogouglass 域
let defaults = UserDefaults.standard

struct Config: Equatable {
    var style: NSGlassEffectView.Style = .clear
    var cornerRadius: CGFloat = 0
    var maxRadius: CGFloat = 20
    var insetX: CGFloat = -6
    var insetY: CGFloat = -3
    var tint: NSColor?
    // 以下为 NSGlassEffectView 的内部属性，-1 表示不改，保持系统默认
    var variant = 11        // 11 = 和 Dock 同类的透镜玻璃（clear 默认是 2，偏毛玻璃）
    var scrim = -1
    var subdued = -1
    var adaptive = -1
    var opacity: CGFloat = 1
    var shadowOpacity: CGFloat = 0.12
    var shadowRadius: CGFloat = 10

    static func load() -> Config {
        var c = Config()
        func num(_ k: String) -> CGFloat? { defaults.object(forKey: k) == nil ? nil : CGFloat(defaults.double(forKey: k)) }
        func int(_ k: String) -> Int? { defaults.object(forKey: k) == nil ? nil : defaults.integer(forKey: k) }
        if defaults.string(forKey: "style") == "regular" { c.style = .regular }
        c.cornerRadius = num("cornerRadius") ?? c.cornerRadius
        c.maxRadius = num("maxRadius") ?? c.maxRadius
        // 兼容旧的 inset（四周统一）
        let inset = num("inset")
        c.insetX = num("insetX") ?? inset ?? c.insetX
        c.insetY = num("insetY") ?? inset ?? c.insetY
        if let s = defaults.string(forKey: "tint") {
            let v = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if v.count == 4, v[3] > 0 { c.tint = NSColor(srgbRed: v[0], green: v[1], blue: v[2], alpha: v[3]) }
        }
        c.variant = int("variant") ?? c.variant
        c.scrim = int("scrim") ?? c.scrim
        c.subdued = int("subdued") ?? c.subdued
        c.adaptive = int("adaptive") ?? c.adaptive
        if let o = num("opacity") { c.opacity = min(max(o, 0.05), 1) }
        c.shadowOpacity = num("shadowOpacity") ?? c.shadowOpacity
        c.shadowRadius = num("shadowRadius") ?? c.shadowRadius
        return c
    }

    func radius(forHeight h: CGFloat) -> CGFloat {
        cornerRadius <= 0 ? min(h / 2, maxRadius) : min(cornerRadius, h / 2)
    }
}

// 设置内部属性；超出范围的值会让 AppKit 直接崩溃，所以先限定范围。
// 系统没有对应的 setter 时（苹果以后改掉了）直接跳过，退回公开样式。
func applyPrivate(_ g: NSGlassEffectView, _ c: Config) {
    func set(_ key: String, _ v: Int, _ range: ClosedRange<Int>) {
        guard range.contains(v), g.responds(to: NSSelectorFromString("set\(key):")) else { return }
        g.setValue(v, forKey: key)
    }
    set("_variant", c.variant, 0...40)
    set("_scrimState", c.scrim, 0...1)
    set("_subduedState", c.subdued, 0...1)
    set("_adaptiveAppearance", c.adaptive, 0...2)
    g.alphaValue = c.opacity
}

// 窗口比玻璃大一圈，留给自绘阴影
let shadowMargin: CGFloat = 24

final class GlassPanel: NSPanel {
    let glass = NSGlassEffectView()
    private let shadowLayer = CALayer()
    private let shadowMask = CAShapeLayer()
    private var config = Config()

    init(level: Int) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = NSWindow.Level(rawValue: level)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false          // 系统窗口阴影会给玻璃加一圈深色描边，改用下面的自绘柔和阴影
        ignoresMouseEvents = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let root = NSView()
        root.wantsLayer = true
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOffset = CGSize(width: 0, height: -2)
        shadowLayer.mask = shadowMask
        shadowMask.fillRule = .evenOdd
        root.layer?.addSublayer(shadowLayer)
        root.addSubview(glass)
        contentView = root
    }

    func apply(_ c: Config) {
        config = c
        glass.style = c.style
        glass.tintColor = c.tint
        applyPrivate(glass, c)
        layoutGlass()
    }

    // 玻璃铺在窗口中间，阴影只画在玻璃外面（挖掉里面，免得透过透明玻璃把背景弄脏）
    func layoutGlass() {
        guard let root = contentView, root.bounds.width > shadowMargin * 2, root.bounds.height > shadowMargin * 2 else { return }
        let bounds = root.bounds
        let g = bounds.insetBy(dx: shadowMargin, dy: shadowMargin)
        glass.frame = g
        let r = config.radius(forHeight: g.height)
        glass.cornerRadius = r

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let shape = CGPath(roundedRect: g, cornerWidth: r, cornerHeight: r, transform: nil)
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = shape
        shadowLayer.shadowOpacity = Float(config.shadowOpacity)
        shadowLayer.shadowRadius = config.shadowRadius
        let mask = CGMutablePath()
        mask.addRect(bounds)
        mask.addPath(shape)
        shadowMask.frame = bounds
        shadowMask.path = mask
        CATransaction.commit()
    }

    // glassFrame：玻璃本身在屏幕上的位置
    func place(glassFrame: CGRect) {
        let f = glassFrame.insetBy(dx: -shadowMargin, dy: -shadowMargin)
        guard frame != f else { return }
        setFrame(f, display: true, animate: false)
        layoutGlass()
    }
}

final class Follower {
    private var sogouPIDs: Set<pid_t> = []
    private var watched: [CGWindowID: Int] = [:]      // 搜狗窗口 -> 层级
    private var panels: [CGWindowID: GlassPanel] = [:]
    private var config = Config.load()
    private var lastScan = Date.distantPast
    private var lastVisible = Date.distantPast
    private var tickCount = 0
    private var skinActive = true

    // 暂停时收起所有玻璃
    var isEnabled = true {
        didSet { if !isEnabled { panels.values.forEach { $0.orderOut(nil) } } }
    }

    func start() {
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
    }

    // 每秒重新扫描一次搜狗的弹出窗口（层级很高的那些）
    private func rescan() {
        lastScan = Date()
        defaults.synchronize()   // 读到 defaults write 的最新值
        let newConfig = Config.load()
        if newConfig != config { config = newConfig; panels.values.forEach { $0.apply(config) } }
        // 用户在搜狗里换成了别的（不透明）皮肤，就不再垫玻璃
        skinActive = SkinInstaller.isActive
        if !skinActive { panels.values.forEach { $0.orderOut(nil) } }

        sogouPIDs = Set(NSWorkspace.shared.runningApplications
            .filter { ($0.bundleIdentifier ?? "").hasPrefix("com.sogou.inputmethod") }
            .map { $0.processIdentifier })
        guard let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return }
        var found: [CGWindowID: Int] = [:]
        for w in all {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, sogouPIDs.contains(pid),
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let layer = w[kCGWindowLayer as String] as? Int, layer >= 1000 else { continue }
            found[id] = layer
        }
        watched = found
        for id in panels.keys where found[id] == nil { panels.removeValue(forKey: id)?.close() }
    }

    private func tick() {
        guard isEnabled else { return }
        tickCount &+= 1
        let now = Date()
        // 候选框 2 秒没出现就降到 40Hz 轮询，出现后立刻回到 120Hz
        if now.timeIntervalSince(lastVisible) > 2, tickCount % 3 != 0 { return }
        if now.timeIntervalSince(lastScan) > 1 { rescan() }
        guard skinActive, !watched.isEmpty else { return }
        let ids = Array(watched.keys)
        var ptrs = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard let arr = CFArrayCreate(nil, &ptrs, ptrs.count, nil),
              let desc = CGWindowListCreateDescriptionFromArray(arr) as? [[String: Any]] else { return }
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        var seen = Set<CGWindowID>()

        for w in desc {
            guard let id = w[kCGWindowNumber as String] as? CGWindowID else { continue }
            seen.insert(id)
            let onscreen = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
            let alpha = (w[kCGWindowAlpha as String] as? Double) ?? 0
            var r = CGRect.zero
            if let b = w[kCGWindowBounds as String] as? NSDictionary { r = CGRect(dictionaryRepresentation: b) ?? .zero }

            guard onscreen, alpha > 0.01, r.width > 24, r.height > 16 else {
                panels[id]?.orderOut(nil)
                continue
            }
            // CG 坐标（左上原点）-> AppKit 坐标（左下原点）
            let glassFrame = CGRect(x: r.minX, y: primaryH - r.maxY, width: r.width, height: r.height)
                .insetBy(dx: config.insetX, dy: config.insetY)
            let panel = panels[id] ?? {
                let p = GlassPanel(level: (watched[id] ?? 2147483629) - 1)
                p.apply(config)
                panels[id] = p
                return p
            }()
            panel.place(glassFrame: glassFrame)
            if !panel.isVisible { panel.orderFrontRegardless() }
            lastVisible = now
        }
        for id in watched.keys where !seen.contains(id) { panels[id]?.orderOut(nil) }
    }
}
