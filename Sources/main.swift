// SogouGlass 入口：菜单栏图标 + 玻璃跟随 + 首次运行自动安装透明皮肤
// 命令行：
//   --uninstall        还原搜狗默认皮肤、移除本皮肤、取消开机自启，然后退出（给 uninstall.sh 用）
//   --demo x,y,w,h     只在该位置（AppKit 坐标）显示一块玻璃 6 秒，用于截图调参
import AppKit
import ServiceManagement

let skinVersion = "1"   // 皮肤内容有变化时加一，已安装的用户启动后会自动更新皮肤

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let follower = Follower()
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ note: Notification) {
        guard SkinInstaller.isSogouInstalled else {
            alert("没有找到搜狗输入法", "请先安装搜狗输入法 Mac 版，再打开 SogouGlass。")
            NSApp.terminate(nil); return
        }
        if defaults.string(forKey: "installedSkinVersion") != skinVersion
            || !FileManager.default.fileExists(atPath: SkinInstaller.installedSkinURL.path) {
            installSkin()
        } else if !SkinInstaller.isActive {
            SkinInstaller.switchTo(SkinInstaller.installedSkinURL.path)   // 上次退出时切回了默认皮肤
        }
        setupMenu()
        follower.start()
    }

    func installSkin() {
        guard let bundled = Bundle.main.url(forResource: "LiquidGlass", withExtension: nil) else {
            alert("皮肤文件缺失", "App 包里没有 LiquidGlass 皮肤，请重新运行 install.sh。"); return
        }
        do {
            try SkinInstaller.install(from: bundled)
            defaults.set(skinVersion, forKey: "installedSkinVersion")
            if let c = defaults.string(forKey: "hotColor").flatMap(SkinInstaller.HotColor.init(rawValue:)), c != .blue {
                SkinInstaller.setHotColor(c)
            }
        } catch {
            alert("皮肤安装失败", error.localizedDescription)
        }
    }

    // MARK: 菜单栏

    func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "drop", accessibilityDescription: "SogouGlass")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // 每次打开菜单时按当前状态重建，勾选状态始终准确
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "SogouGlass · 搜狗液态玻璃", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        if !SkinInstaller.isActive {
            let warn = NSMenuItem(title: "⚠︎ 搜狗当前没在用液态玻璃皮肤", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        menu.addItem(.separator())

        menu.addItem(item("液态玻璃", #selector(toggleGlass), on: follower.isEnabled))
        let colorItem = NSMenuItem(title: "首选词颜色", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        let current = defaults.string(forKey: "hotColor") ?? SkinInstaller.HotColor.blue.rawValue
        for c in SkinInstaller.HotColor.allCases {
            let it = item(c.title, #selector(pickColor(_:)), on: c.rawValue == current)
            it.representedObject = c.rawValue
            colorMenu.addItem(it)
        }
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)
        menu.addItem(item("重新应用皮肤", #selector(reapplySkin)))
        menu.addItem(.separator())
        menu.addItem(item("开机自动启动", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        menu.addItem(.separator())
        menu.addItem(item("还原搜狗默认皮肤并退出", #selector(restoreAndQuit)))
        menu.addItem(item("退出", #selector(quit), key: "q"))
    }

    func item(_ title: String, _ sel: Selector, on: Bool = false, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        it.target = self
        it.state = on ? .on : .off
        return it
    }

    @objc func toggleGlass() {
        follower.isEnabled.toggle()
        // 关掉玻璃时皮肤是全透明的，顺便切回默认皮肤，打开时再切回来
        if follower.isEnabled { SkinInstaller.switchTo(SkinInstaller.installedSkinURL.path) }
        else { SkinInstaller.switchTo(SkinInstaller.defaultSkinPath) }
    }

    @objc func pickColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let c = SkinInstaller.HotColor(rawValue: raw) else { return }
        defaults.set(raw, forKey: "hotColor")
        SkinInstaller.setHotColor(c)
    }

    @objc func reapplySkin() { installSkin() }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            alert("设置开机启动失败", "\(error.localizedDescription)\n可以在 系统设置 → 通用 → 登录项 里手动添加 SogouGlass。")
        }
    }

    @objc func restoreAndQuit() {
        SkinInstaller.switchTo(SkinInstaller.defaultSkinPath)
        NSApp.terminate(nil)
    }

    @objc func quit() {
        // 皮肤是透明的，没有玻璃会只剩文字，所以退出时切回默认皮肤；下次启动会自动切回来
        SkinInstaller.switchTo(SkinInstaller.defaultSkinPath)
        NSApp.terminate(nil)
    }

    func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate()
        a.runModal()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let args = CommandLine.arguments

if args.contains("--uninstall") {
    SkinInstaller.uninstall()
    try? SMAppService.mainApp.unregister()
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))   // 等通知发出去
    exit(0)
}

if let i = args.firstIndex(of: "--demo"), i + 1 < args.count {
    let d = args[i + 1].split(separator: ",").compactMap { Double($0) }
    if d.count == 4 {
        let c = Config.load()
        let p = GlassPanel(level: NSWindow.Level.statusBar.rawValue)
        p.apply(c)
        p.place(glassFrame: CGRect(x: d[0], y: d[1], width: d[2], height: d[3]).insetBy(dx: c.insetX, dy: c.insetY))
        p.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { exit(0) }
        app.run()
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
