import Cocoa

// Lightweight self-updater. Downloads the release DMG, then hands off to a
// detached shell helper that waits for this app to quit, verifies the new bundle
// (version + "Verge Dev" signature), swaps it into place, and relaunches. No
// Sparkle, no framework. The stable cert means the swapped app keeps its
// Accessibility grant.
enum Updater {
    static func installUpdate(tag: String, dmgURL: URL) {
        let dmgPath = NSTemporaryDirectory() + "Verge-\(tag).dmg"
        let task = URLSession.shared.downloadTask(with: dmgURL) { loc, resp, err in
            guard let loc = loc, err == nil,
                  (resp as? HTTPURLResponse)?.statusCode ?? 0 < 400 else {
                DispatchQueue.main.async { fail("Couldn't download the update.") }; return
            }
            try? FileManager.default.removeItem(atPath: dmgPath)
            do { try FileManager.default.moveItem(at: loc, to: URL(fileURLWithPath: dmgPath)) }
            catch { DispatchQueue.main.async { fail("Couldn't save the update.") }; return }
            DispatchQueue.main.async { swapAndRelaunch(dmgPath: dmgPath, tag: tag) }
        }
        task.resume()
    }

    private static func swapAndRelaunch(dmgPath: String, tag: String) {
        let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v "))
        let appPath = Bundle.main.bundlePath   // e.g. /Applications/Verge.app
        // Helper runs AFTER we quit. It refuses to swap unless the new bundle is the
        // expected version AND signed by "Verge Dev" — so a tampered/partial DMG
        // can never replace a working install.
        let script = """
        #!/bin/bash
        while pgrep -x Verge >/dev/null; do sleep 0.3; done
        MNT=$(hdiutil attach "\(dmgPath)" -nobrowse -noautoopen 2>/dev/null | grep -oE '/Volumes/[^\\t]+' | tail -1)
        NEW="$MNT/Verge.app"
        V=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$NEW/Contents/Info.plist" 2>/dev/null || echo "")
        if [ "$V" = "\(version)" ] && codesign -dv "$NEW" 2>&1 | grep -q "Authority=Verge Dev"; then
          TMP="\(appPath).new"
          rm -rf "$TMP"
          if cp -R "$NEW" "$TMP"; then     # stage a full copy, then swap atomically
            rm -rf "\(appPath)"
            mv "$TMP" "\(appPath)"
          fi
        fi
        hdiutil detach "$MNT" >/dev/null 2>&1 || true
        rm -f "\(dmgPath)"
        open "\(appPath)"
        rm -f "$0"
        """
        let scriptPath = NSTemporaryDirectory() + "verge-update.sh"
        do { try script.write(toFile: scriptPath, atomically: true, encoding: .utf8) }
        catch { fail("Couldn't stage the update."); return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [scriptPath]
        do { try p.run() } catch { fail("Couldn't start the updater."); return }
        NSApp.terminate(nil)   // helper waits for exit, then swaps + relaunches
    }

    private static func fail(_ msg: String) {
        let a = NSAlert()
        a.messageText = "Update failed"
        a.informativeText = msg + " You can download it manually from the releases page."
        a.addButton(withTitle: "OK")
        a.runModal()
    }
}
