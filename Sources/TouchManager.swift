import Cocoa

// C callback cannot capture context -> route through the shared singleton.
private let contactCallback: MTContactCallbackFunction = { _, touchesPtr, count, _, _ in
    guard let touchesPtr = touchesPtr else { return 0 }
    let buffer = UnsafeBufferPointer(start: touchesPtr, count: Int(count))
    GestureController.shared.handle(touches: buffer)
    return 0
}

final class TouchManager {
    private var device: MTDeviceRef?

    // ponytail: default device only (built-in trackpad). Multi-device / hot-plug
    // via MTDeviceCreateList if someone needs an external Magic Trackpad too.
    func start() {
        guard let dev = MTDeviceCreateDefault() else {
            NSLog("Verge: no multitouch device found")
            return
        }
        device = dev
        var devID: UInt64 = 0
        MTDeviceGetDeviceID(dev, &devID)
        Haptic.setup(deviceID: devID)
        MTRegisterContactFrameCallback(dev, contactCallback)
        MTDeviceStart(dev, 0)
        NSLog("Verge: multitouch started")
    }

    func stop() {
        guard let dev = device else { return }
        MTUnregisterContactFrameCallback(dev, contactCallback)
        MTDeviceStop(dev)
        device = nil
    }
}
