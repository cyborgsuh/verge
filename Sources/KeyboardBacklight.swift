import Cocoa
import ObjectiveC.runtime

// Keyboard backlight control via the private CoreBrightness framework.
//
// Why not media keys like volume/brightness: synthetic ILLUMINATION_UP/DOWN NX
// events do nothing on Apple Silicon, so this is the only path that works.
// Trade-off: macOS draws no HUD for it (we tick the taptic instead).
//
// Loaded with dlopen and every call guarded, deliberately NOT hard-linked: a
// future macOS that moves or drops this private framework then just makes the
// feature no-op instead of stopping the whole app from launching.
//
// Method signatures below are the real ObjC type encodings:
//   brightnessForKeyboard:              f24@0:8Q16    (UInt64) -> Float
//   setBrightness:forKeyboard:          B28@0:8f16Q20 (Float, UInt64) -> Bool
//   isKeyboardBuiltIn:                  B24@0:8Q16    (UInt64) -> Bool
//   enableAutoBrightness:forKeyboard:   B28@0:8B16Q20 (Bool, UInt64) -> Bool
final class KeyboardBacklight {
    static let shared = KeyboardBacklight()

    private typealias GetFn    = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetFn    = @convention(c) (AnyObject, Selector, Float, UInt64) -> ObjCBool
    private typealias QueryFn  = @convention(c) (AnyObject, Selector, UInt64) -> ObjCBool
    private typealias EnableFn = @convention(c) (AnyObject, Selector, ObjCBool, UInt64) -> ObjCBool

    private var client: AnyObject?
    private var getFn: GetFn?
    private var setFn: SetFn?
    private var builtInFn: QueryFn?
    private var autoOnFn: QueryFn?
    private var enableAutoFn: EnableFn?
    private let getSel = NSSelectorFromString("brightnessForKeyboard:")
    private let setSel = NSSelectorFromString("setBrightness:forKeyboard:")
    private var autoDisabled = false     // only touch auto-brightness once, on first write

    /// True when the private API resolved and the feature can actually work.
    private(set) var available = false

    private init() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return }
        let c = cls.init()
        // Every selector must exist; if Apple changes any of them we stay unavailable.
        guard let g = class_getMethodImplementation(cls, getSel),
              let s = class_getMethodImplementation(cls, setSel),
              let b = class_getMethodImplementation(cls, NSSelectorFromString("isKeyboardBuiltIn:")),
              let a = class_getMethodImplementation(cls, NSSelectorFromString("isAutoBrightnessEnabledForKeyboard:")),
              let e = class_getMethodImplementation(cls, NSSelectorFromString("enableAutoBrightness:forKeyboard:")),
              c.responds(to: getSel), c.responds(to: setSel)
        else { return }
        client = c
        getFn = unsafeBitCast(g, to: GetFn.self)
        setFn = unsafeBitCast(s, to: SetFn.self)
        builtInFn = unsafeBitCast(b, to: QueryFn.self)
        autoOnFn = unsafeBitCast(a, to: QueryFn.self)
        enableAutoFn = unsafeBitCast(e, to: EnableFn.self)
        available = true
    }

    // The backlight ID is assigned at boot and changes across reboots, so it is
    // resolved per call. A stale ID silently accepts writes and does nothing.
    private func builtInKeyboardID() -> UInt64? {
        guard let c = client,
              let ids = c.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?
                  .takeRetainedValue() as? [NSNumber]   // `copy` => we own it
        else { return nil }
        let builtInSel = NSSelectorFromString("isKeyboardBuiltIn:")
        let builtIn = ids.first { builtInFn?(c, builtInSel, $0.uint64Value).boolValue ?? false }
        return (builtIn ?? ids.first)?.uint64Value
    }

    // nil = not probed yet, true/false = whether the illumination media key
    // actually moves the backlight on this Mac.
    private var mediaKeyWorks: Bool?

    /// One step up or down.
    ///
    /// Prefers the illumination media key, because then the system (or whatever
    /// notch app has taken over the HUD) draws the level indicator for free, the
    /// same way volume and screen brightness work. The first press is checked
    /// against the actual level: if nothing moved, this Mac ignores the key and
    /// we fall back to writing CoreBrightness directly (works, but silent).
    func adjust(up: Bool, step: Float) {
        if mediaKeyWorks == false {
            nudge(up ? step : -step)
            return
        }
        let before = level()
        MediaKey.post(up ? NX_KEYTYPE_ILLUMINATION_UP : NX_KEYTYPE_ILLUMINATION_DOWN)
        guard mediaKeyWorks == nil else { return }
        // Probe once, shortly after the first press, then remember the answer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.mediaKeyWorks == nil else { return }
            guard let b = before, let a = self.level() else { return }
            self.mediaKeyWorks = abs(a - b) > 0.001
            if self.mediaKeyWorks == false { self.nudge(up ? step : -step) }
        }
    }

    /// Current level, 0...1. nil when unavailable.
    func level() -> Float? {
        guard available, let c = client, let id = builtInKeyboardID() else { return nil }
        return getFn?(c, getSel, id)
    }

    /// Nudge by `delta` (e.g. +0.05). Returns the new level, or nil if it failed.
    @discardableResult
    func nudge(_ delta: Float) -> Float? {
        guard available, let c = client, let id = builtInKeyboardID(),
              let get = getFn, let set = setFn else { return nil }
        // Ambient auto-brightness suppresses the backlight and overrides manual
        // writes, so it has to go off. Done once, and only if it was actually on,
        // to keep the side effect as small as possible.
        if !autoDisabled {
            autoDisabled = true
            if autoOnFn?(c, NSSelectorFromString("isAutoBrightnessEnabledForKeyboard:"), id).boolValue == true {
                _ = enableAutoFn?(c, NSSelectorFromString("enableAutoBrightness:forKeyboard:"), false, id)
            }
        }
        let next = min(max(get(c, getSel, id) + delta, 0), 1)
        return set(c, setSel, next, id).boolValue ? next : nil
    }
}
