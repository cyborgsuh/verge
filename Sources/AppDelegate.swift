import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let touch = TouchManager()
    private var keyMonitor: Any?
    private var updateTag: String?   // set when a newer release exists

    func applicationDidFinishLaunching(_ note: Notification) {
        // authoritative defaults — gesture engine + Preferences read these keys
        UserDefaults.standard.register(defaults: [
            "enabled": true,
            "swapSides": false,
            "edgeZone": 0.045,     // reachable edge strip (0.025 was too tight to hit)
            "stepTravel": 0.05,
            "fineSteps": true,
            "topScrub": true,
            "freezeCursor": true,
            "scrubStep": 1.0,     // 1 second per notch
        ])
        // On very first launch, enable Open-at-Login by default. Once-only, so if
        // the user later turns it off via the menu it stays off.
        if !UserDefaults.standard.bool(forKey: "loginConfigured") {
            UserDefaults.standard.set(true, forKey: "loginConfigured")
            try? SMAppService.mainApp.register()
        }
        requestAccessibility()
        setupMenu()
        touch.start()
        // typing detection: remember the last keystroke time.
        // Skip arrow keys (123-126): our own scrub gesture posts them and they
        // aren't typing — otherwise scrubbing would trip its own guard.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { ev in
            if (123...126).contains(Int(ev.keyCode)) { return }
            GestureController.shared.noteKeyPress()
        }
        // menu-bar app has no main window — show Preferences so launching it
        // (Finder double-click / `open`) visibly opens something.
        PreferencesController.shared.show()
        // nudge if a newer release is out (no auto-download, just a menu item)
        UpdateCheck.run { [weak self] tag in
            self?.updateTag = tag
            self?.rebuildMenu()
        }
    }

    // Double-clicking the app while it's already running -> reopen Preferences.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        PreferencesController.shared.show()
        return true
    }

    func applicationWillTerminate(_ note: Notification) {
        CGAssociateMouseAndMouseCursorPosition(1)  // never leave the cursor frozen
        touch.stop()
    }

    private func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSLog("Verge: needs Accessibility permission to post media keys")
        }
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.statusIcon()
        statusItem.button?.toolTip = "Verge"
        rebuildMenu()
    }

    // Custom template glyph: vertical slider track + knob + up/down chevrons.
    // Template = single black shape; the system recolors it for light/dark bars.
    private static func statusIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            // track
            NSBezierPath(roundedRect: NSRect(x: 5.0, y: 1.5, width: 2.4, height: 15.0),
                         xRadius: 1.2, yRadius: 1.2).fill()
            // knob riding the track
            NSBezierPath(ovalIn: NSRect(x: 2.9, y: 8.4, width: 6.6, height: 6.6)).fill()
            // tiny up/down chevrons
            let ch = NSBezierPath()
            ch.lineWidth = 1.5
            ch.lineCapStyle = .round
            ch.lineJoinStyle = .round
            ch.move(to: NSPoint(x: 11.4, y: 13.2))
            ch.line(to: NSPoint(x: 13.4, y: 15.2))
            ch.line(to: NSPoint(x: 15.4, y: 13.2))
            ch.move(to: NSPoint(x: 11.4, y: 4.8))
            ch.line(to: NSPoint(x: 13.4, y: 2.8))
            ch.line(to: NSPoint(x: 15.4, y: 4.8))
            ch.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }

    private func rebuildMenu() {
        // Read state straight from UserDefaults — the gesture engine reads the
        // same keys live, so the menu just mirrors them.
        let d = UserDefaults.standard
        let enabled = (d.object(forKey: "enabled") as? Bool) ?? true
        let swapSides = d.bool(forKey: "swapSides")
        let m = NSMenu()

        if let tag = updateTag {
            let up = NSMenuItem(title: "Update available: \(tag) ↗", action: #selector(openRelease), keyEquivalent: "")
            up.target = self
            m.addItem(up)
            m.addItem(.separator())
        }

        let en = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        en.state = enabled ? .on : .off; en.target = self
        m.addItem(en)

        let sw = NSMenuItem(title: "Swap sides", action: #selector(toggleSwap), keyEquivalent: "")
        sw.state = swapSides ? .on : .off; sw.target = self
        m.addItem(sw)

        let sc = NSMenuItem(title: "Video scrub (top edge)", action: #selector(toggleScrub), keyEquivalent: "")
        sc.state = ((d.object(forKey: "topScrub") as? Bool) ?? true) ? .on : .off; sc.target = self
        m.addItem(sc)

        let fc = NSMenuItem(title: "Freeze cursor while sliding", action: #selector(toggleFreeze), keyEquivalent: "")
        fc.state = ((d.object(forKey: "freezeCursor") as? Bool) ?? true) ? .on : .off; fc.target = self
        m.addItem(fc)

        let li = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        li.state = SMAppService.mainApp.status == .enabled ? .on : .off; li.target = self
        m.addItem(li)

        m.addItem(.separator())
        let l = swapSides ? "Left = volume · Right = brightness"
                          : "Left = brightness · Right = volume"
        m.addItem(NSMenuItem(title: l, action: nil, keyEquivalent: ""))
        m.addItem(NSMenuItem(title: "Slide up ↑ raise · down ↓ lower", action: nil, keyEquivalent: ""))

        m.addItem(.separator())
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        m.addItem(prefs)
        m.addItem(NSMenuItem(title: "Quit Verge", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = m
    }

    @objc private func openPreferences() { PreferencesController.shared.show() }

    @objc private func openRelease() { NSWorkspace.shared.open(UpdateCheck.releaseURL) }

    @objc private func toggleEnabled() {
        let d = UserDefaults.standard
        d.set(!((d.object(forKey: "enabled") as? Bool) ?? true), forKey: "enabled")
        rebuildMenu()
    }

    @objc private func toggleSwap() {
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: "swapSides"), forKey: "swapSides")
        rebuildMenu()
    }

    @objc private func toggleScrub() {
        let d = UserDefaults.standard
        d.set(!((d.object(forKey: "topScrub") as? Bool) ?? true), forKey: "topScrub")
        rebuildMenu()
    }

    @objc private func toggleFreeze() {
        let d = UserDefaults.standard
        d.set(!((d.object(forKey: "freezeCursor") as? Bool) ?? true), forKey: "freezeCursor")
        rebuildMenu()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Verge: login item toggle failed: \(error)")
        }
        rebuildMenu()
    }
}
