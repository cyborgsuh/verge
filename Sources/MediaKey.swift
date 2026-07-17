import Cocoa

let NX_KEYTYPE_SOUND_UP: Int32 = 0
let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
let NX_KEYTYPE_BRIGHTNESS_UP: Int32 = 2
let NX_KEYTYPE_BRIGHTNESS_DOWN: Int32 = 3

// Synthesizes a hardware media key so the system (and Boring Notch) react.
// fine: adds Shift+Option -> quarter steps (1/64 ≈ 1.6% per notch instead of 6.25%).
enum MediaKey {
    static func post(_ key: Int32, fine: Bool = false) {
        emit(key, down: true, fine: fine)
        emit(key, down: false, fine: fine)
    }
    private static func emit(_ key: Int32, down: Bool, fine: Bool) {
        var flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
        if fine { flags.formUnion([.shift, .option]) }
        let data1 = Int((key << 16) | ((down ? 0xa : 0xb) << 8))
        guard let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                  modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                  subtype: 8, data1: data1, data2: -1), let cg = ev.cgEvent else { return }
        cg.post(tap: .cghidEventTap)
    }

    // Arrow key tap for video scrubbing (Right/Left seek in most players).
    static func postArrow(right: Bool) {
        let code: CGKeyCode = right ? 124 : 123
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    }
}
