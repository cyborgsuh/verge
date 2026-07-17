import Cocoa

// Video scrubbing. Prefers exact 1s seeks through Boring Notch's
// mediaremote-adapter (Apple-signed perl bypasses the MediaRemote lockdown).
// Sessions that refuse external seek (e.g. Chrome/YouTube) fall back to
// arrow keys (player-defined step, 5s on YouTube).
final class Scrubber {
    static let shared = Scrubber()

    private let adapter = "/Applications/boringNotch.app/Contents/Resources/mediaremote-adapter.pl"
    private let framework = "/Applications/boringNotch.app/Contents/Frameworks/MediaRemoteAdapter.framework"
    private var adapterPresent: Bool { FileManager.default.fileExists(atPath: adapter) }

    private let queue = DispatchQueue(label: "verge.scrub")  // serialize adapter calls
    private var base: Double?        // elapsed at gesture start (nil = unknown/unsupported)
    private var duration: Double = .infinity
    private var offset: Double = 0   // accumulated ±1s notches this gesture
    private var seekWork: DispatchWorkItem?
    private var sessionSeekable = true

    private var stepSeconds: Double {
        (UserDefaults.standard.object(forKey: "scrubStep") as? Double) ?? 1.0
    }

    // Called when a top-edge track arms: snapshot the playing position.
    func begin() {
        offset = 0
        base = nil
        sessionSeekable = adapterPresent
        guard sessionSeekable else { return }
        queue.async { [self] in
            guard let out = run(["get"]),
                  let data = out.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let e = j["elapsedTime"] as? Double else { return }
            base = e
            duration = (j["duration"] as? Double) ?? .infinity
        }
    }

    // One notch: right = forward.
    func notch(right: Bool) {
        queue.async { [self] in
            if sessionSeekable, let b = base {
                offset += right ? stepSeconds : -stepSeconds
                let target = min(max(b + offset, 0), duration)
                seekWork?.cancel()
                let w = DispatchWorkItem { [self] in
                    let micros = Int(target * 1_000_000)
                    if run(["seek", String(micros)]) == nil {
                        sessionSeekable = false           // player refused: arrows from now on
                        MediaKey.postArrow(right: right)
                    }
                }
                seekWork = w
                queue.asyncAfter(deadline: .now() + 0.1, execute: w)  // debounce burst of notches
            } else {
                MediaKey.postArrow(right: right)
            }
        }
    }

    // Run adapter; nil on failure. Called on `queue` only.
    private func run(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [adapter, framework] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
