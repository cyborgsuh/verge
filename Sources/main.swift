import Cocoa
import CoreAudio

// Diagnostic: does the fine (Shift+Option) media key actually move volume?
//   ./Verge.app/Contents/MacOS/Verge --testfine
if CommandLine.arguments.contains("--testfine") {
    func vol() -> Float {
        var dev = AudioDeviceID(0); var sz = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a1 = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                            mScope: kAudioObjectPropertyScopeGlobal,
                                            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a1, 0, nil, &sz, &dev)
        var a2 = AudioObjectPropertyAddress(mSelector: 0x766d7663,
                                            mScope: kAudioObjectPropertyScopeOutput,
                                            mElement: kAudioObjectPropertyElementMain)
        var v = Float32(0); var s2 = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(dev, &a2, 0, nil, &s2, &v)
        return v
    }
    print("AX trusted:", AXIsProcessTrusted())
    let v0 = vol()
    MediaKey.post(NX_KEYTYPE_SOUND_UP)                 // plain
    usleep(400_000)
    let v1 = vol()
    MediaKey.post(NX_KEYTYPE_SOUND_UP, fine: true)     // shift+option quarter
    usleep(400_000)
    let v2 = vol()
    print(String(format: "start %.4f | after plain %.4f (Δ%.4f) | after fine %.4f (Δ%.4f)",
                 v0, v1, v1 - v0, v2, v2 - v1))
    exit(0)
}

// Diagnostic: can we read + seek the system now-playing session (MediaRemote)?
//   Play a video first, then: ./Verge.app/Contents/MacOS/Verge --testseek
if CommandLine.arguments.contains("--testseek") {
    var elapsed: Double? = nil
    let sem = DispatchSemaphore(value: 0)
    MRMediaRemoteGetNowPlayingInfo(DispatchQueue.global()) { info in
        if let d = info as NSDictionary?,
           let e = d["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double {
            elapsed = e
        }
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 2)
    guard let e = elapsed else {
        print("BLOCKED: no now-playing info readable (macOS MediaRemote restriction)")
        exit(1)
    }
    print(String(format: "elapsed now: %.1fs — seeking +10s...", e))
    MRMediaRemoteSetElapsedTime(e + 10)
    usleep(800_000)
    let sem2 = DispatchSemaphore(value: 0)
    MRMediaRemoteGetNowPlayingInfo(DispatchQueue.global()) { info in
        if let d = info as NSDictionary?,
           let e2 = d["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double {
            print(String(format: "elapsed after: %.1fs  =>  seek %@", e2, e2 > e + 5 ? "WORKS" : "did NOT move"))
        } else { print("re-read failed") }
        sem2.signal()
    }
    _ = sem2.wait(timeout: .now() + 2)
    exit(0)
}

// Diagnostic: measure the real reachable edge x on this trackpad.
//   ./Verge.app/Contents/MacOS/Verge --probe   (then slide a finger along an edge)
if CommandLine.arguments.contains("--probe") {
    final class P { static var minX: Float = 1; static var maxX: Float = 0; static var n = 0 }
    let cb: MTContactCallbackFunction = { _, tp, count, _, _ in
        guard let tp = tp else { return 0 }
        for i in 0..<Int(count) where tp[i].state == 4 {
            let x = tp[i].normalized.position.x
            P.minX = min(P.minX, x); P.maxX = max(P.maxX, x); P.n += 1
        }
        return 0
    }
    guard let dev = MTDeviceCreateDefault() else { print("no multitouch device"); exit(1) }
    MTRegisterContactFrameCallback(dev, cb); MTDeviceStart(dev, 0)
    print("Slide one finger along the LEFT edge, then the RIGHT edge — 6s...")
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 6))
    print(String(format: "samples:%d  min x seen: %.3f  max x seen: %.3f", P.n, P.minX, P.maxX))
    print("=> set edgeZone a bit above min, and below (1 - max)")
    exit(0)
}

// Runnable self-check for the stepping math (no XCTest needed):
//   ./Verge.app/Contents/MacOS/Verge --selftest
if CommandLine.arguments.contains("--selftest") {
    precondition(notches(dy: 0.00, step: 0.05) == 0)
    precondition(notches(dy: 0.04, step: 0.05) == 0)
    precondition(notches(dy: 0.06, step: 0.05) == 1)
    precondition(notches(dy: 0.16, step: 0.05) == 3)
    precondition(notches(dy: -0.06, step: 0.05) == -1)
    precondition(notches(dy: -0.16, step: 0.05) == -3)
    print("selftest ok")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // menu-bar only, no Dock icon
app.run()
