// 搜狗候选框出现时截取其周围区域。用法: watch <输出目录> <最多张数> <总秒数>
import AppKit
let out = CommandLine.arguments[1], maxShots = Int(CommandLine.arguments[2])!, total = Double(CommandLine.arguments[3])!
let minH = CommandLine.arguments.count > 4 ? CGFloat(Double(CommandLine.arguments[4])!) : 16
let start = Date(); var shots = 0; var last = Date.distantPast
while Date().timeIntervalSince(start) < total && shots < maxShots {
    let pids = Set(NSWorkspace.shared.runningApplications.filter { ($0.bundleIdentifier ?? "").hasPrefix("com.sogou.inputmethod") }.map { $0.processIdentifier })
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list {
        guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
              let layer = w[kCGWindowLayer as String] as? Int, layer >= 1000,
              let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b),
              r.width > 24, r.height > minH, Date().timeIntervalSince(last) > 1.2 else { continue }
        usleep(150_000)
        let pad: CGFloat = 40
        let rr = r.insetBy(dx: -pad, dy: -pad)
        shots += 1; last = Date()
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-R\(Int(rr.minX)),\(Int(rr.minY)),\(Int(rr.width)),\(Int(rr.height))", "\(out)/cand\(shots).png"]
        try? p.run(); p.waitUntilExit()
        print("shot \(shots) window=\(r)"); fflush(stdout)
        break
    }
    usleep(50_000)
}
print("done shots=\(shots)")
