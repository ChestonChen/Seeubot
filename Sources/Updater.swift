import Foundation

/// Checks GitHub Releases for a newer version and reports the tag if one exists.
enum Updater {
    static let repo = "ChestonChen/Seeubot"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var releasesURL: URL { URL(string: "https://github.com/\(repo)/releases/latest")! }

    /// Fetches the latest release tag; calls back (on an arbitrary queue) with the tag
    /// string only if it is newer than the running version, otherwise nil.
    static func checkLatest(_ completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            completion(nil); return
        }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else { completion(nil); return }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            completion(isNewer(latest, than: currentVersion) ? tag : nil)
        }.resume()
    }

    /// Semantic-ish comparison: "1.2" > "1.1", "1.10" > "1.9".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
