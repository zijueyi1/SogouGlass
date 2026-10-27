// 宣传片素材录制：等搜狗候选框第一次出现时开始录屏，同时记录候选框位置（供 make_promo 自动对准镜头）。
// 用法: swift promo/record.swift <输出目录> [秒数=40]
// 输出: <目录>/screen.mov 和 <目录>/candidates.tsv（t, x, y, w, h，CG 屏幕坐标，t 从录屏开始计）
// 需要录屏权限。
import AppKit

let outDir = CommandLine.arguments[1]
let seconds = Double(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "40") ?? 40
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func sogouCandidates() -> [CGRect] {
    let pids = Set(NSWorkspace.shared.runningApplications
        .filter { ($0.bundleIdentifier ?? "").hasPrefix("com.sogou.inputmethod") }.map { $0.processIdentifier })
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { w in
        guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
              let layer = w[kCGWindowLayer as String] as? Int, layer >= 1000,
              let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b),
              r.width > 24, r.height > 16 else { return nil }
        return r
    }
}

print("等待搜狗候选框出现……（开始打字即开始录制）"); fflush(stdout)
while sogouCandidates().isEmpty { usleep(30_000) }

let rec = Process()
rec.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
rec.arguments = ["-v", "-x", "-V", "\(Int(seconds))", "\(outDir)/screen.mov"]
try rec.run()
let start = Date()
print("开始录制 \(Int(seconds)) 秒"); fflush(stdout)

var log = ""
while rec.isRunning {
    let t = Date().timeIntervalSince(start)
    for r in sogouCandidates() {
        log += String(format: "%.3f\t%.0f\t%.0f\t%.0f\t%.0f\n", t, r.minX, r.minY, r.width, r.height)
    }
    usleep(33_000)
}
try log.write(toFile: "\(outDir)/candidates.tsv", atomically: true, encoding: .utf8)
print("录制完成：\(outDir)/screen.mov，候选框记录 \(log.split(separator: "\n").count) 条")
