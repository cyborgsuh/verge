import Cocoa

enum Zone { case left, right, top }

// MT touch phase we care about (fully on the surface).
private let MT_STATE_TOUCHING: Int32 = 4

// Pure stepping math — how many notches a travel `dy` crosses.
// Positive = up/right, negative = down/left. Unit-testable (--selftest).
func notches(dy: Float, step: Float) -> Int {
    if dy >= step { return Int(dy / step) }
    if dy <= -step { return -Int(-dy / step) }
    return 0
}

final class GestureController {
    static let shared = GestureController()

    // tuning knobs (normalized 0..1 trackpad coords) — read from UserDefaults on
    // every call so a Preferences window can retune at runtime, no restart.
    private var edge: Float {      // arm only at the absolute edge
        // floor 0.04: below that a fingertip can't reach the strip -> never arms.
        Float(min(max((UserDefaults.standard.object(forKey: "edgeZone") as? Double) ?? 0.045, 0.04), 0.10))
    }
    private var dropEdge: Float { edge + 0.08 }  // finger drifted this far inward -> cancel
    private let wanderTol: Float = 0.05  // cross-axis wander this big -> it's a swipe, cancel
    private var step: Float {            // travel per notch
        Float(min(max((UserDefaults.standard.object(forKey: "stepTravel") as? Double) ?? 0.05, 0.02), 0.12))
    }
    private let typingGuard: TimeInterval = 0.6  // ignore gestures right after a keystroke
    private let settle: TimeInterval = 0.045     // finger must be alone this long before firing

    // start = cross-axis position at arm (wander check); anchor = slide-axis position.
    private struct Track { var id: Int32; var zone: Zone; var start: Float; var anchor: Float; var armTime: TimeInterval }
    // true once 2+ fingers seen this contact -> stays disqualified until ALL lift.
    private var multiLatch = false
    private var cursorFrozen = false
    private var frozenAt = CGPoint.zero
    private var active: Track? {
        didSet {  // freeze/unfreeze cursor on gesture start/end
            let now = active != nil, was = oldValue != nil
            guard now != was else { return }
            if now {
                guard freezeCursor else { return }
                frozenAt = CGEvent(source: nil)?.location ?? .zero  // CG (top-left) coords
                CGAssociateMouseAndMouseCursorPosition(0)
                cursorFrozen = true
            } else if cursorFrozen {
                CGAssociateMouseAndMouseCursorPosition(1)
                cursorFrozen = false
            }
        }
    }
    private var lastKeyPress: TimeInterval = 0

    var enabled: Bool { (UserDefaults.standard.object(forKey: "enabled") as? Bool) ?? true }
    var swapSides: Bool { UserDefaults.standard.bool(forKey: "swapSides") }
    var topScrub: Bool { (UserDefaults.standard.object(forKey: "topScrub") as? Bool) ?? true }
    var freezeCursor: Bool { (UserDefaults.standard.object(forKey: "freezeCursor") as? Bool) ?? true }

    func noteKeyPress() { lastKeyPress = CACurrentMediaTime() }

    // debug: VERGE_DEBUG=1 -> log raw touch frames (sampled) to Console
    private let debug = ProcessInfo.processInfo.environment["VERGE_DEBUG"] == "1"
    private var dbgCount = 0

    func handle(touches: UnsafeBufferPointer<MTTouch>) {
        if debug {
            dbgCount += 1
            if dbgCount % 15 == 0, let f = touches.first {  // ~every 15th frame
                let states = touches.map { String($0.state) }.joined(separator: ",")
                NSLog("VERGE dbg n=%d states=[%@] x=%.3f y=%.3f edge=%.3f",
                      touches.count, states, f.normalized.position.x, f.normalized.position.y, edge)
            }
        }
        guard enabled else { if debug { NSLog("VERGE bail: disabled") }; active = nil; return }
        if CACurrentMediaTime() - lastKeyPress < typingGuard {
            if debug { NSLog("VERGE bail: typing guard") }; active = nil; return
        }

        // Single-finger edge slide only. Count the WHOLE contact lifecycle
        // (make/touch/break/linger = states 3..6), not just fully-touching(4):
        // during a scroll/pinch a second finger is in state 3 or 6 on the very
        // frames the first reads 4, so a state==4-only count would see just one
        // and arm. Counting 3..6 catches the second finger the instant it lands.
        let contacts = touches.filter { $0.state >= 3 && $0.state <= 6 }
        if contacts.isEmpty {           // everything lifted -> reset the latch
            if multiLatch && debug { NSLog("VERGE latch cleared") }
            multiLatch = false; active = nil; return
        }
        if contacts.count > 1 {         // scroll / pinch / swipe / 3-finger
            if !multiLatch && debug { NSLog("VERGE latch: %d contacts", contacts.count) }
            multiLatch = true; active = nil; return
        }
        // one contact — but if this gesture was EVER multi-finger, stay dead
        // until a full lift, so a scroll that flickers to 1 finger can't sneak in.
        if multiLatch { active = nil; return }
        let t = contacts[0]
        guard t.state == MT_STATE_TOUCHING else { active = nil; return }  // acting finger fully down

        let x = t.normalized.position.x
        let y = t.normalized.position.y
        let nowT = CACurrentMediaTime()

        if var tr = active, tr.id == t.identifier {
            if cursorFrozen { CGWarpMouseCursorPosition(frozenAt) }  // pin cursor each frame
            // slide axis: y for L/R edges, x for top edge
            let vertical = tr.zone != .top
            let nearEdge: Bool
            switch tr.zone {
            case .left:  nearEdge = x < dropEdge
            case .right: nearEdge = x > (1 - dropEdge)
            case .top:   nearEdge = y > (1 - dropEdge)
            }
            let cross = vertical ? x : y
            // Wander = cross-axis drift means a swipe, not an edge slide -> cancel.
            // Only for L/R edges: sliding the TOP edge horizontally makes Y wobble
            // naturally, and `nearEdge` (y>0.88) already keeps it pinned to the top,
            // so the wander check just kills the top slide. Skip it there.
            let wandered = tr.zone != .top && abs(cross - tr.start) > wanderTol
            if !nearEdge || wandered {
                if debug { NSLog("VERGE cancel: nearEdge=%d wander=%.3f", nearEdge ? 1 : 0, abs(cross - tr.start)) }
                active = nil; return
            }
            let pos = vertical ? y : x
            // Settle: hold off firing until the finger has been alone `settle`
            // seconds. A scroll/pinch's second finger lands inside this window and
            // trips the latch above, so it never gets here. Re-anchor while settling
            // so post-settle notches count from the settled position (no jump).
            if nowT - tr.armTime < settle {
                tr.anchor = pos
                active = tr
                return
            }
            let step = self.step   // snapshot: keep notches() and anchor advance consistent
            let n = notches(dy: pos - tr.anchor, step: step)
            if n != 0 {
                let up = n > 0
                if debug { NSLog("VERGE FIRE zone=%d n=%d", tr.zone == .left ? 0 : (tr.zone == .right ? 1 : 2), n) }
                for _ in 0..<abs(n) { fire(zone: tr.zone, up: up) }
                tr.anchor += Float(n) * step
                active = tr
            }
        } else if x < edge {
            if debug { NSLog("VERGE ARM left x=%.3f edge=%.3f", x, edge) }
            active = Track(id: t.identifier, zone: .left, start: x, anchor: y, armTime: nowT)
        } else if x > (1 - edge) {
            if debug { NSLog("VERGE ARM right x=%.3f edge=%.3f", x, edge) }
            active = Track(id: t.identifier, zone: .right, start: x, anchor: y, armTime: nowT)
        } else if topScrub && y > (1 - edge) {
            if debug { NSLog("VERGE ARM top y=%.3f", y) }
            active = Track(id: t.identifier, zone: .top, start: y, anchor: x, armTime: nowT)
            Scrubber.shared.begin()   // snapshot playing position for 1s seeks
        } else {
            if debug { NSLog("VERGE no-arm x=%.3f y=%.3f edge=%.3f", x, y, edge) }
            active = nil
        }
    }

    private func fire(zone: Zone, up: Bool) {
        if zone == .top {  // top edge: video scrub (up == right)
            Scrubber.shared.notch(right: up)
            DispatchQueue.main.async { Haptic.tick() }
            return
        }
        // default: left edge = brightness, right edge = volume. swapSides flips.
        let isVolume = (zone == .right) != swapSides
        let key: Int32 = isVolume ? (up ? NX_KEYTYPE_SOUND_UP : NX_KEYTYPE_SOUND_DOWN)
                                  : (up ? NX_KEYTYPE_BRIGHTNESS_UP : NX_KEYTYPE_BRIGHTNESS_DOWN)
        let fine = (UserDefaults.standard.object(forKey: "fineSteps") as? Bool) ?? true
        DispatchQueue.main.async { MediaKey.post(key, fine: fine); Haptic.tick() }
    }
}
