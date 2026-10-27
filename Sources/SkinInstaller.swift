// 皮肤安装：把 App 自带的透明皮肤装进搜狗的皮肤目录、登记到皮肤列表，并通知搜狗立即切换。
import Foundation

enum SkinInstaller {
    static let skinID = "lg2027"
    static let skinName = "液态玻璃"
    static let fm = FileManager.default

    static var sogouRoot: URL {
        fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Sogou/InputMethod")
    }
    static var installedSkinURL: URL { sogouRoot.appendingPathComponent("Skins/\(skinID)_\(skinName)") }
    static let defaultSkinPath = "/Library/Input Methods/SogouInput.app/Contents/Resources/Skins/搜狗输入法默认皮肤"
    static let sogouAppPath = "/Library/Input Methods/SogouInput.app"

    static var isSogouInstalled: Bool { fm.fileExists(atPath: sogouAppPath) }

    // 搜狗当前使用的皮肤目录（记在 UserPreferences.plist 的 keySkinPath）
    static var currentSkinPath: String? {
        let url = sogouRoot.appendingPathComponent("SogouPY/UserPreferences.plist")
        guard let d = NSDictionary(contentsOf: url) else { return nil }
        return d["keySkinPath"] as? String
    }

    static var isActive: Bool { currentSkinPath == installedSkinURL.path }

    // 让搜狗切换到指定皮肤（和搜狗皮肤管理器发的是同一个通知）
    static func switchTo(_ path: String) {
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("kSogouNotifyToSogouInputChangeSkinPath"),
            object: path, userInfo: ["keySkinPath": path, "skinPath": path], deliverImmediately: true)
    }

    // 先切到默认皮肤再切回来，强制搜狗重新读取皮肤文件
    static func reload() {
        switchTo(defaultSkinPath)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { switchTo(installedSkinURL.path) }
    }

    static func install(from bundled: URL) throws {
        try fm.createDirectory(at: installedSkinURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: installedSkinURL.path) { try fm.removeItem(at: installedSkinURL) }
        try fm.copyItem(at: bundled, to: installedSkinURL)
        register()
        reload()
    }

    static func uninstall() {
        switchTo(defaultSkinPath)
        unregister()
        try? fm.removeItem(at: installedSkinURL)
    }

    // 登记到皮肤列表，皮肤管理器里才能看到它（不登记也能用）
    private static func register() {
        editPlist("SogouPY/skinInfo.plist") { (root: inout [String: Any]) in
            var arr = (root["skinArray"] as? [[String: Any]] ?? []).filter { $0["skin_id"] as? String != skinID }
            arr.insert(["show": "1", "skin_id": skinID, "skin_name": skinName,
                        "skin_path": installedSkinURL.path, "skin_type": "0"], at: 0)
            root["skinArray"] = arr
        }
        editPlist("SogouPY/skinUsedRecent.plist") { (arr: inout [[String: Any]]) in
            arr.removeAll { $0["skinId"] as? String == skinID }
            arr.insert(["defaultSkin": 0, "paySkin": 0, "skin_type": "0", "skinId": skinID,
                        "skinName": skinName, "skinPath": installedSkinURL.path], at: 0)
        }
    }

    private static func unregister() {
        editPlist("SogouPY/skinInfo.plist") { (root: inout [String: Any]) in
            root["skinArray"] = (root["skinArray"] as? [[String: Any]] ?? []).filter { $0["skin_id"] as? String != skinID }
        }
        editPlist("SogouPY/skinUsedRecent.plist") { (arr: inout [[String: Any]]) in
            arr.removeAll { $0["skinId"] as? String == skinID }
        }
    }

    private static func editPlist<T>(_ rel: String, _ body: (inout T) -> Void) {
        let url = sogouRoot.appendingPathComponent(rel)
        guard let data = try? Data(contentsOf: url),
              var obj = try? PropertyListSerialization.propertyList(from: data, format: nil) as? T else { return }
        body(&obj)
        if let out = try? PropertyListSerialization.data(fromPropertyList: obj, format: .xml, options: 0) {
            try? out.write(to: url, options: .atomic)
        }
    }

    // 首选词颜色。搜狗展开面板的细框也用这个颜色，换成石墨灰后细框会变得很淡
    enum HotColor: String, CaseIterable {
        case blue, graphite
        var title: String { self == .blue ? "蓝色" : "石墨灰（展开面板细框更淡）" }
        func value(dark: Bool) -> String {
            switch self {
            case .blue: return dark ? "10,132,255,1.00" : "0,122,255,1.00"
            case .graphite: return dark ? "235,235,245,1.00" : "60,60,67,1.00"
            }
        }
    }

    static func setHotColor(_ c: HotColor) {
        for (dir, dark) in [("Skin", false), ("SkinDark", true)] {
            for file in ["skin.plist", "skin_10.plist"] {
                let url = installedSkinURL.appendingPathComponent("\(dir)/\(file)")
                guard let data = try? Data(contentsOf: url),
                      var root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      var info = root["SkinInfo"] as? [String: Any],
                      var font = info["FontSetting"] as? [String: Any],
                      var hot = font["HotStyle"] as? [String: Any] else { continue }
                hot["FontColor"] = c.value(dark: dark)
                font["HotStyle"] = hot; info["FontSetting"] = font; root["SkinInfo"] = info
                if let out = try? PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0) {
                    try? out.write(to: url, options: .atomic)
                }
            }
        }
        reload()
    }
}
