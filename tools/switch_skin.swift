// 让搜狗切换到指定皮肤目录（模拟皮肤管理器发出的通知）
// 用法: swift tools/switch_skin.swift <皮肤目录>
import Foundation
let p = CommandLine.arguments[1]
let c = DistributedNotificationCenter.default()
c.postNotificationName(NSNotification.Name("kSogouNotifyToSogouInputChangeSkinPath"), object: p, userInfo: ["keySkinPath": p, "skinPath": p], deliverImmediately: true)
RunLoop.current.run(until: Date().addingTimeInterval(0.5))
print("posted")
