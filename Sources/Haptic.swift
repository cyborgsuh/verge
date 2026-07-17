import Cocoa

// Direct taptic-engine feedback via private MTActuator. Works from a background
// menu-bar app (NSHapticFeedbackManager does not).
enum Haptic {
    private static var actuator: MTActuatorRef?
    // actuation patterns: 1..6, 15, 16. 3 = light detent tick.
    private static let pattern: Int32 = 3

    static func setup(deviceID: UInt64) {
        guard deviceID != 0, let act = MTActuatorCreateFromDeviceID(deviceID) else {
            NSLog("Verge: no taptic actuator"); return
        }
        MTActuatorOpen(act)
        actuator = act
        NSLog("Verge: taptic actuator ready")
    }

    static func tick() {
        guard let act = actuator else { return }
        MTActuatorActuate(act, pattern, 0, 0.0, 0.0)
    }
}
