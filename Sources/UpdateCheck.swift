import Cocoa

// Lightweight update check: ask GitHub for the latest release tag on launch and,
// if it's newer than this build, surface a menu item linking to it. No Sparkle,
// no dependency, no auto-download — just a nudge.
enum UpdateCheck {
    static let repo = "cyborgsuh/verge"
    static var releaseURL: URL { URL(string: "https://github.com/\(repo)/releases/latest")! }

    // Fetch latest release; call `onNewer(tag, dmgURL)` on main only if it beats
    // the running version and ships a Verge.dmg asset. Silent on any error.
    static func run(onNewer: @escaping (String, URL) -> Void) {
        guard let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: api)
        req.setValue("Verge", forHTTPHeaderField: "User-Agent")   // GitHub API requires a UA
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = j["tag_name"] as? String else { return }
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            guard isNewer(tag, than: current) else { return }
            let assets = j["assets"] as? [[String: Any]]
            guard let dmg = assets?.first(where: { ($0["name"] as? String) == "Verge.dmg" }),
                  let urlStr = dmg["browser_download_url"] as? String,
                  let url = URL(string: urlStr) else { return }
            DispatchQueue.main.async { onNewer(tag, url) }
        }.resume()
    }

    // Semver-ish compare: "v0.1.3" > "0.1.2" -> true. Missing parts count as 0.
    static func isNewer(_ remote: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "v ")).split(separator: ".").map { Int($0) ?? 0 }
        }
        let r = parts(remote), c = parts(current)
        for i in 0..<max(r.count, c.count) {
            let a = i < r.count ? r[i] : 0, b = i < c.count ? c[i] : 0
            if a != b { return a > b }
        }
        return false
    }
}
