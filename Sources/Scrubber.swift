import Cocoa

// Video scrubbing. Prefers exact 1s seeks through Boring Notch's mediaremote
// adapter (works in native players: QuickTime, IINA, VLC, Music...). Sessions
// that refuse external seek (browsers / YouTube) fall back to arrow keys.
//
// Throttled, not debounced: a debounce dropped every notch but the last, so a
// whole top-edge slide fired one seek at the end and felt dead. Here each edge
// slide coalesces to the LATEST target and acts at a steady rate, so scrubbing
// gives feedback continuously.
final class Scrubber {
    static let shared = Scrubber()

    private let adapter = "/Applications/boringNotch.app/Contents/Resources/mediaremote-adapter.pl"
    private let framework = "/Applications/boringNotch.app/Contents/Frameworks/MediaRemoteAdapter.framework"
    private var adapterPresent: Bool { FileManager.default.fileExists(atPath: adapter) }

    private let queue = DispatchQueue(label: "verge.scrub")  // serialize adapter calls
    private var base: Double?         // elapsed at gesture start (nil = not seekable)
    private var duration = Double.infinity
    private var offset = 0.0          // accumulated ±step this gesture
    private var sessionSeekable = true
    private var lastActionAt = 0.0    // throttle clock (CACurrentMediaTime)

    private let seekThrottle = 0.12   // native seek: ~8/sec max (perl spawn is slow)
    private let arrowThrottle = 0.22  // arrows are big jumps (~5s) -> don't spam

    private var stepSeconds: Double {
        (UserDefaults.standard.object(forKey: "scrubStep") as? Double) ?? 1.0
    }

    // Top-edge track armed: snapshot the playing position for exact seeks.
    func begin() {
        queue.async { [self] in
            offset = 0; base = nil; lastActionAt = 0
            sessionSeekable = adapterPresent
            guard sessionSeekable else { return }
            if let out = run(["get"]),
               let d = out.data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let e = j["elapsedTime"] as? Double {
                base = e
                duration = (j["duration"] as? Double) ?? .infinity
            } else {
                sessionSeekable = false   // can't read now-playing -> arrows
            }
        }
    }

    // One notch: right = forward.
    func notch(right: Bool) {
        queue.async { [self] in
            offset += right ? stepSeconds : -stepSeconds
            let now = CACurrentMediaTime()

            if sessionSeekable, let b = base {
                guard now - lastActionAt >= seekThrottle else { return }   // coalesce to latest
                lastActionAt = now
                let target = min(max(b + offset, 0), duration)
                if run(["seek", String(Int(target * 1_000_000))]) == nil {
                    sessionSeekable = false                                // refused -> arrows
                    arrow(right)
                }
            } else {
                guard now - lastActionAt >= arrowThrottle else { return }
                lastActionAt = now
                arrow(right)
            }
        }
    }

    private func arrow(_ right: Bool) {
        DispatchQueue.main.async { MediaKey.postArrow(right: right) }
    }

    // Run adapter; nil on failure (non-zero exit). Called on `queue` only.
    private func run(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [adapter, framework] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice   // discard; never let stderr fill
        do { try p.run() } catch { return nil }
        // Drain stdout to EOF BEFORE waitUntilExit. `get` returns base64 artwork
        // that overflows the 64KB pipe buffer; waiting first deadlocks (child
        // blocked writing, parent blocked waiting) and jams the whole scrub queue.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
