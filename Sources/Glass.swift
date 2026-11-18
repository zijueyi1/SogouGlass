// 玻璃跟随：找到搜狗输入法的弹出窗口，在它正下方一层放一块系统原生的液态玻璃（NSGlassEffectView）并实时跟随。
// 搜狗那边用全透明皮肤，只负责显示文字。
// 调参（改完一秒内生效）：
//   defaults write com.zijue.sogouglass style -string clear|regular
//   defaults write com.zijue.sogouglass cornerRadius -float 0      (<=0 胶囊形，圆角不超过 maxRadius)
//   defaults write com.zijue.sogouglass maxRadius -float 16
//   defaults write com.zijue.sogouglass insetX -float -6           (负数=玻璃比候选框宽出多少)
//   defaults write com.zijue.sogouglass insetY -float -1
//   defaults write com.zijue.sogouglass tint -string "1,1,1,0.0"   (r,g,b,a 着色)
//   defaults write com.zijue.sogouglass variant -int 11            (内部玻璃变体 0-40，11 = 透镜玻璃)
//   defaults write com.zijue.sogouglass adaptive -int 0            (0-2，随背景调整外观)
//   defaults write com.zijue.sogouglass scrim -int 0 / subdued -int 0
//   defaults write com.zijue.sogouglass opacity -float 0.8         (玻璃整体不透明度)
//   defaults write com.zijue.sogouglass shadowOpacity -float 0.12  (外投影，0 关闭)
//   defaults write com.zijue.sogouglass shadowRadius -float 10
//   defaults write com.zijue.sogouglass minimumBackgroundBrightness -float 0.58  (原生暗部托亮，0 关闭)
// 内部属性改回默认需要重启本程序
import AppKit

// 以 App 包运行时 standard 即 com.zijue.sogouglass 域
let defaults = UserDefaults.standard

struct Config: Equatable {
    var useSystemMaterial = true
    var style: NSGlassEffectView.Style = .clear
    var cornerRadius: CGFloat = 0
    var maxRadius: CGFloat = 16
    var insetX: CGFloat = -6
    var insetY: CGFloat = -1
    var tint: NSColor?
    // 以下为 NSGlassEffectView 的内部属性，-1 表示不改，保持系统默认
    var variant = 11        // 11 = 和 Dock 同类的透镜玻璃（clear 默认是 2，偏毛玻璃）
    var scrim = -1
    var subdued = -1
    var adaptive = -1
    var opacity: CGFloat = 1
    var shadowOpacity: CGFloat = 0.12
    var shadowRadius: CGFloat = 10
    var minimumBackgroundBrightness: CGFloat = 0.58

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
        if let floor = num("minimumBackgroundBrightness"), floor.isFinite {
            c.minimumBackgroundBrightness = min(max(floor, 0), 1)
        }
        c.useSystemMaterial = defaults.string(forKey: "materialPreset") == "system"
        if c.useSystemMaterial {
            // 系统公开的通透材质；regular 的厚底色会改变透明候选框的外观。
            c.style = .clear
            c.variant = -1
            c.scrim = -1
            c.subdued = -1
            c.adaptive = -1
            c.tint = nil
            c.opacity = 1
            c.minimumBackgroundBrightness = 0
        }
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
    private let brightnessFloor = NSView()
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
        // 与已验证样例相同：在同一块原生玻璃内进行 Lighten 合成。
        // 用合成器的原生混合名称，不挂 CIFilter，不切换到 Core Image 进程内渲染。
        brightnessFloor.wantsLayer = true
        brightnessFloor.autoresizingMask = [.width, .height]
        glass.contentView = brightnessFloor
        root.addSubview(glass)
        contentView = root
    }

    func apply(_ c: Config) {
        config = c
        hasShadow = false
        updateMaterial()
        layoutGlass()
    }

    private func updateMaterial() {
        let c = config
        glass.style = c.style
        glass.tintColor = c.tint
        applyPrivate(glass, c)
        if c.minimumBackgroundBrightness > 0 {
            let floor = c.minimumBackgroundBrightness
            brightnessFloor.layer?.backgroundColor = NSColor(srgbRed: floor, green: floor, blue: floor, alpha: 1).cgColor
            brightnessFloor.layer?.compositingFilter = "lightenBlendMode"
        } else {
            brightnessFloor.layer?.compositingFilter = nil
            brightnessFloor.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    // 玻璃铺在窗口中间，阴影只画在玻璃外面（挖掉里面，免得透过透明玻璃把背景弄脏）
    func layoutGlass() {
        guard let root = contentView, root.bounds.width > shadowMargin * 2, root.bounds.height > shadowMargin * 2 else { return }
        let bounds = root.bounds
        let g = bounds.insetBy(dx: shadowMargin, dy: shadowMargin)
        glass.frame = g
        brightnessFloor.frame = glass.bounds
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

@MainActor
final class Follower {
    private var sogouPIDs: Set<pid_t> = []
    private var watched: [CGWindowID: Int] = [:]      // 搜狗窗口 -> 层级
    private var panels: [CGWindowID: GlassPanel] = [:]
    private var config = Config.load()
    private var lastScan = Date.distantPast
    private var lastActivity = Date.distantPast
    private var skinActive = true
    private var otherWindowIDs: Set<CGWindowID> = []
    private var lastSeen: [CGWindowID: Date] = [:]
    private var lastWindowPoll = Date.distantPast
    private var timer: Timer?
    private var pollInterval: TimeInterval = 0

    // 真正降低定时器唤醒频率，而不是让 120Hz 定时器不断空转。
    private let activeInterval: TimeInterval = 1.0 / 60.0
    private let idleInterval: TimeInterval = 0.1

    // 暂停时收起所有玻璃
    var isEnabled = true {
        didSet {
            if !isEnabled { hidePanels() }
            lastScan = .distantPast
            updateTimer()
        }
    }

    func start() {
        guard timer == nil else { return }
        tick()
    }

    private func hidePanels() {
        for panel in panels.values where panel.isVisible { panel.orderOut(nil) }
    }

    private func updateTimer() {
        let interval: TimeInterval
        if !isEnabled || !skinActive || sogouPIDs.isEmpty {
            interval = 1.0
        } else if Date().timeIntervalSince(lastActivity) <= 0.5 {
            interval = activeInterval
        } else {
            interval = idleInterval
        }
        guard timer == nil || pollInterval != interval else { return }
        timer?.invalidate()
        pollInterval = interval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = interval * 0.1
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    // 每秒刷新配置和搜狗进程，不再全量读取窗口属性。
    private func rescan() {
        lastScan = Date()
        defaults.synchronize()   // 读到 defaults write 的最新值
        let newConfig = Config.load()
        if newConfig != config { config = newConfig; panels.values.forEach { $0.apply(config) } }
        // 用户在搜狗里换成了别的（不透明）皮肤，就不再垫玻璃
        skinActive = SkinInstaller.isActive
        if !skinActive { hidePanels() }

        let newPIDs = Set(NSWorkspace.shared.runningApplications
            .filter { ($0.bundleIdentifier ?? "").hasPrefix("com.sogou.inputmethod") }
            .map { $0.processIdentifier })
        if newPIDs != sogouPIDs {
            sogouPIDs = newPIDs
            watched.removeAll()
            otherWindowIDs.removeAll()
            lastSeen.removeAll()
            for panel in panels.values { panel.close() }
            panels.removeAll()
        }
        // 没有搜狗进程或用户已换皮肤时，不扫描其他应用的窗口。
        guard skinActive, !sogouPIDs.isEmpty else {
            watched.removeAll()
            for panel in panels.values { panel.close() }
            panels.removeAll()
            return
        }
        // 清理已经消失的候选窗，不保留长期累积的窗口和图层。
        let cutoff = Date().addingTimeInterval(-10)
        for id in Array(lastSeen.keys) where lastSeen[id]! < cutoff {
            lastSeen.removeValue(forKey: id)
            watched.removeValue(forKey: id)
            panels.removeValue(forKey: id)?.close()
        }
    }

    private func tick() {
        defer { updateTimer() }
        guard isEnabled else { return }
        let now = Date()
        if now.timeIntervalSince(lastScan) > 1 { rescan() }
        guard skinActive, !sogouPIDs.isEmpty else { return }
        // 没有近期键鼠活动时，仅每秒做一次兜底发现，静止的候选窗也不持续高频轮询。
        // 这里只读系统提供的空闲时长，不接收事件内容，也不安装键盘钩子。
        if now.timeIntervalSince(lastWindowPoll) < 1, SGInputIdleSeconds() > 0.35 {
            return
        }
        lastWindowPoll = now
        // ID 列表不含窗口属性字典。只为新出现的窗口和可见的搜狗窗口取详细属性；
        // 候选窗隐藏时不再反复向 WindowServer 请求它的完整描述。
        guard let data = SGCopyVisibleWindowIDs() as Data? else {
            hidePanels()
            return
        }
        let visibleIDs = data.withUnsafeBytes { Set($0.bindMemory(to: CGWindowID.self)) }
        otherWindowIDs.formIntersection(visibleIDs)
        for (id, panel) in panels where !visibleIDs.contains(id) && panel.isVisible { panel.orderOut(nil) }
        let ids = Array(visibleIDs.subtracting(otherWindowIDs))
        guard !ids.isEmpty else { return }
        var ptrs = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard let arr = CFArrayCreate(nil, &ptrs, ptrs.count, nil),
              let desc = CGWindowListCreateDescriptionFromArray(arr) as? [[String: Any]] else { return }
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        var seen = Set<CGWindowID>()

        for w in desc {
            guard let id = w[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, sogouPIDs.contains(pid) else {
                otherWindowIDs.insert(id)
                continue
            }
            guard let layer = w[kCGWindowLayer as String] as? Int, layer >= 1000 else { continue }
            watched[id] = layer
            lastSeen[id] = now
            seen.insert(id)
            let onscreen = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
            let alpha = (w[kCGWindowAlpha as String] as? Double) ?? 0
            var r = CGRect.zero
            if let b = w[kCGWindowBounds as String] as? NSDictionary { r = CGRect(dictionaryRepresentation: b) ?? .zero }

            guard onscreen, alpha > 0.01, r.width > 24, r.height > 16 else {
                if let panel = panels[id], panel.isVisible { panel.orderOut(nil) }
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
            if !panel.isVisible || panel.frame != glassFrame.insetBy(dx: -shadowMargin, dy: -shadowMargin) {
                lastActivity = now
            }
            panel.place(glassFrame: glassFrame)
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        for id in watched.keys where !seen.contains(id) {
            if let panel = panels[id], panel.isVisible { panel.orderOut(nil) }
        }
    }
}
