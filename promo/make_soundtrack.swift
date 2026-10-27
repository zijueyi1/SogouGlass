// 宣传片配乐：程序合成的原创配乐（无版权问题），按画面转场对齐，然后合入视频。
// 用法: swift promo/make_soundtrack.swift <视频.mp4> <输出.mp4> [配乐.wav]
// 转场时间与 make_promo.swift 的 timeline 一致，改了时间线记得同步下面的 cuts。
import AVFoundation
import Foundation

let sr = 44100.0
let cuts: [Double] = [0, 2.4, 4.8, 9.1, 11.7, 18.7, 21.5]   // 每个镜头的开始时间
let endHit = 21.5                                            // 结尾标题出现
let videoURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])
let wavURL = URL(fileURLWithPath: CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : outURL.deletingPathExtension().path + ".wav")

let duration = CMTimeGetSeconds(AVURLAsset(url: videoURL).duration)
let n = Int(duration * sr)
var dryL = [Float](repeating: 0, count: n), dryR = dryL
var sendL = dryL, sendR = dryL      // 送混响

func midi(_ m: Double) -> Double { 440 * pow(2, (m - 69) / 12) }

// 加一段声音：f(t) 给出该时刻的样本值，pan -1 左 … 1 右，rev 送混响比例
func add(_ t0: Double, _ len: Double, pan: Double = 0, rev: Double = 0.35, _ f: (Double) -> Double) {
    let s0 = max(0, Int(t0 * sr)), s1 = min(n, Int((t0 + len) * sr))
    guard s1 > s0 else { return }
    let gl = Float(sqrt((1 - pan) / 2)), gr = Float(sqrt((1 + pan) / 2))
    for i in s0..<s1 {
        let v = Float(f(Double(i) / sr - t0))
        dryL[i] += v * gl; dryR[i] += v * gr
        sendL[i] += v * gl * Float(rev); sendR[i] += v * gr * Float(rev)
    }
}

// MARK: - 乐器

// 铺底长音：多个轻微失谐的正弦 + 少量泛音，慢起慢收
func pad(_ notes: [Double], _ t0: Double, _ len: Double, amp: Double = 0.035) {
    for (k, m) in notes.enumerated() {
        let f = midi(m)
        add(t0, len + 1.5, pan: k % 2 == 0 ? -0.35 : 0.35, rev: 0.6) { t in
            let env = min(t / 0.9, 1) * (t > len ? exp(-(t - len) * 2.5) : 1)
            let w = sin(2 * .pi * f * t) + sin(2 * .pi * f * 1.004 * t) * 0.7 + sin(2 * .pi * f * 0.997 * t) * 0.7
                + sin(2 * .pi * f * 2 * t) * 0.15
            return w * env * amp
        }
    }
}

// 拨弦 / 电钢琴感的短音：几个泛音，高泛音衰减更快
func pluck(_ m: Double, _ t0: Double, amp: Double = 0.11, pan: Double = 0, decay: Double = 2.2) {
    let f = midi(m)
    add(t0, 1.6, pan: pan, rev: 0.45) { t in
        let a = min(t / 0.004, 1)
        return a * (sin(2 * .pi * f * t) * exp(-t * decay)
            + 0.45 * sin(2 * .pi * f * 2 * t) * exp(-t * decay * 1.8)
            + 0.18 * sin(2 * .pi * f * 3 * t) * exp(-t * decay * 2.6)
            + 0.08 * sin(2 * .pi * f * 4.01 * t) * exp(-t * decay * 3.5)) * amp
    }
}

func bass(_ m: Double, _ t0: Double, _ len: Double, amp: Double = 0.16) {
    let f = midi(m)
    add(t0, len + 0.3, rev: 0.05) { t in
        let env = min(t / 0.02, 1) * (t > len ? exp(-(t - len) * 12) : exp(-t * 0.6))
        return (sin(2 * .pi * f * t) + 0.25 * sin(2 * .pi * f * 2 * t)) * env * amp
    }
}

func kick(_ t0: Double, amp: Double = 0.42) {
    add(t0, 0.4, rev: 0.05) { t in
        let ph = 2 * .pi * (45 * t + (120 - 45) / 18 * (1 - exp(-t * 18)))
        return sin(ph) * exp(-t * 9) * amp
    }
}

var seed: UInt64 = 0x9E3779B97F4A7C15
func noise() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(Int64(bitPattern: seed >> 1)) / Double(Int64.max) }

func hat(_ t0: Double, amp: Double = 0.035, pan: Double = 0.2) {
    var prev = 0.0
    add(t0, 0.08, pan: pan, rev: 0.2) { t in
        let x = noise(); let hp = x - prev; prev = x   // 简单高通
        return hp * exp(-t * 60) * amp
    }
}

// 转场"嗖"声：低通噪声，截止频率和音量一起往上推，到 tEnd 时截断
func swoosh(_ tEnd: Double, _ len: Double = 0.7, amp: Double = 0.09) {
    var y = 0.0
    add(tEnd - len, len + 0.05, rev: 0.5) { t in
        let p = min(t / len, 1)
        let a = 0.02 + 0.5 * p * p                 // 低通系数随时间升高 = 越来越亮
        y += a * (noise() - y)
        let env = t < len ? p * p : exp(-(t - len) * 60)
        return y * env * amp * 3
    }
}

// 重音：低频轰鸣 + 一点噪声
func boom(_ t0: Double, amp: Double = 0.38) {
    add(t0, 2.5, rev: 0.4) { t in
        sin(2 * .pi * 48 * t) * exp(-t * 1.6) * amp + noise() * exp(-t * 25) * 0.08
    }
}

// MARK: - 编曲（120 BPM，一拍 0.5 秒）

let beat = 0.5
let chords: [[Double]] = [
    [53, 57, 60, 64],        // Fmaj7
    [45, 52, 55, 60, 64],    // Am7
    [50, 53, 57, 60, 64],    // Dm9
    [46, 50, 53, 57, 62],    // B♭maj7
]
let roots: [Double] = [41, 45, 38, 46]
let chordLen = 4.0   // 每个和弦 2 小节

func chordAt(_ t: Double) -> Int { Int(t / chordLen) % chords.count }

// 铺底：从头到结尾标题
var t = 0.0
while t < endHit {
    let c = chordAt(t)
    // 开场标题时更轻，实拍开始后再铺满
    pad(chords[c], t, min(chordLen, endHit - t), amp: t < cuts[2] ? 0.02 : 0.035)
    t += chordLen
}

// 琶音：开场只零星点几个高音；第一段实拍开始变成八分音符；"一行命令" 后收
var step = 0
var tb = 0.0
while tb < endHit {
    let c = chords[chordAt(tb)]
    let tones = c + c.map { $0 + 12 }
    if tb < cuts[2] {
        if step % 4 == 0 { pluck(tones[(step / 4) % tones.count] + 12, tb, amp: 0.06, pan: step % 8 == 0 ? -0.4 : 0.4, decay: 1.4) }
    } else if tb < cuts[5] {
        let soft = tb >= cuts[3] && tb < cuts[4]          // "不是贴图" 那段收一点
        let pattern = [0, 2, 4, 6, 7, 6, 4, 2]
        pluck(tones[pattern[step % 8] % tones.count] + 12, tb, amp: soft ? 0.06 : 0.1, pan: step % 2 == 0 ? -0.3 : 0.3)
    }
    step += 1
    tb += beat / 2
}

// 低音和鼓：第一段实拍开始；"不是贴图" 停；展开那段回来并加踩镲
var tk = cuts[2]
while tk < cuts[5] {
    let inBreak = tk >= cuts[3] && tk < cuts[4]
    if !inBreak {
        if Int((tk / beat).rounded()) % 2 == 0 { kick(tk) }
        if tk >= cuts[4] { hat(tk + beat / 2) }
        if Int((tk / beat).rounded()) % 4 == 0 { bass(roots[chordAt(tk)], tk, beat * 1.8) }
    }
    tk += beat
}

// 转场
for c in cuts.dropFirst() { swoosh(c, c == endHit ? 2.6 : 0.7, amp: c == endHit ? 0.05 : 0.06) }
boom(cuts[3], amp: 0.25)                         // "不是贴图。"
pluck(76, cuts[3] + 0.35, amp: 0.1, decay: 1.2)  // "是真正的玻璃。" 的点缀
boom(endHit, amp: 0.5)                           // 结尾标题：全曲最重的一下
pad([41, 53, 57, 60, 64, 67], endHit, duration - endHit - 1.2, amp: 0.06)    // 结尾 Fmaj9 长音
for (k, m) in [77.0, 81, 84, 88].enumerated() { pluck(m, endHit + Double(k) * 0.12, amp: 0.08, pan: Double(k) * 0.25 - 0.4, decay: 0.9) }

// MARK: - 混响（Schroeder：4 个梳状 + 2 个全通，左右声道延迟略不同）

func reverb(_ x: [Float], spread: Int) -> [Float] {
    let combs = [1116, 1188, 1277, 1356].map { $0 + spread }
    var out = [Float](repeating: 0, count: x.count)
    for d in combs {
        var buf = [Float](repeating: 0, count: d), i = 0, lp: Float = 0
        for s in 0..<x.count {
            let y = buf[i]
            lp = y * 0.7 + lp * 0.3                       // 阻尼
            buf[i] = x[s] + lp * 0.84
            out[s] += y
            i = (i + 1) % d
        }
    }
    for d in [556 + spread, 441 + spread] {
        var buf = [Float](repeating: 0, count: d), i = 0
        for s in 0..<out.count {
            let b = buf[i], v = out[s]
            out[s] = -v + b
            buf[i] = v + b * 0.5
            i = (i + 1) % d
        }
    }
    return out.map { $0 * 0.25 }
}

let wetL = reverb(sendL, spread: 0), wetR = reverb(sendR, spread: 23)
var L = zip(dryL, wetL).map { $0 + $1 }, R = zip(dryR, wetR).map { $0 + $1 }

// 开头 0.3 秒淡入、结尾 1.2 秒淡出，然后归一化到 -1 dBFS
for i in 0..<n {
    let tt = Double(i) / sr
    let g = Float(min(tt / 0.3, 1) * min((duration - tt) / 1.2, 1))
    L[i] *= g; R[i] *= g
}
let peak = max(L.map(abs).max() ?? 1, R.map(abs).max() ?? 1)
let norm = 0.89 / peak
L = L.map { $0 * norm }; R = R.map { $0 * norm }
print(String(format: "合成完成 %.1f 秒，峰值归一化系数 %.2f", duration, norm))

// MARK: - 写 WAV 并合入视频

let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
pcm.frameLength = AVAudioFrameCount(n)
L.withUnsafeBufferPointer { pcm.floatChannelData![0].update(from: $0.baseAddress!, count: n) }
R.withUnsafeBufferPointer { pcm.floatChannelData![1].update(from: $0.baseAddress!, count: n) }
try? FileManager.default.removeItem(at: wavURL)
do {
    let file = try AVAudioFile(forWriting: wavURL, settings: fmt.settings)
    try file.write(from: pcm)
}

let comp = AVMutableComposition()
let video = AVURLAsset(url: videoURL), audio = AVURLAsset(url: wavURL)
let range = CMTimeRange(start: .zero, duration: video.duration)
let vt = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
try vt.insertTimeRange(range, of: video.tracks(withMediaType: .video)[0], at: .zero)
let at = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
try at.insertTimeRange(range, of: audio.tracks(withMediaType: .audio)[0], at: .zero)

try? FileManager.default.removeItem(at: outURL)
let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)!
ex.outputURL = outURL
ex.outputFileType = .mp4
let sem = DispatchSemaphore(value: 0)
ex.exportAsynchronously { sem.signal() }
sem.wait()
if ex.status == .completed { print("done -> \(outURL.path)") } else { print("导出失败: \(String(describing: ex.error))"); exit(1) }
