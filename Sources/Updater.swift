import Foundation

// 系统 API 速览：
// - Bundle.main.object(forInfoDictionaryKey:)：读取 Info.plist 里的当前 app 版本。
// - URL / URLRequest：构造 GitHub API 请求。
// - URLSession.shared.dataTask：Foundation 网络请求 API，异步拉取 latest release。
// - JSONSerialization：把 GitHub 返回的 JSON data 解析成字典。
// - completion 闭包：异步请求结束后把“是否有新版本”回传给调用方。
/// Checks GitHub Releases for a newer version and reports the tag if one exists.
enum Updater {
    static let repo = "ChestonChen/Seeubot"

    static var currentVersion: String {
        // 系统 API（行级）：Bundle.main.object 读取 Info.plist 中的 app 元信息。
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // 系统 API（行级）：URL 构造系统 URL 对象。
    static var releasesURL: URL { URL(string: "https://github.com/\(repo)/releases/latest")! }

    /// Fetches the latest release tag; calls back (on an arbitrary queue) with the tag
    /// string only if it is newer than the running version, otherwise nil.
    static func checkLatest(_ completion: @escaping (String?) -> Void) {
        // 系统 API（行级）：URL 构造系统 URL 对象。
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            completion(nil); return
        }
        // 系统 API（行级）：URLRequest 构造网络请求对象。
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // 系统 API（行级）：URLSession.dataTask 发起异步网络请求。
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  // 系统 API（行级）：JSONSerialization.jsonObject 把 JSON Data 解析成字典/数组。
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
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
