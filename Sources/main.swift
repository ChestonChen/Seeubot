import AppKit

// 系统 API 速览：
// - CommandLine.arguments：读取启动参数，比如 --stats / --render。
// - JSONEncoder：把 Swift 数据结构编码成 JSON 字符串，方便命令行调试。
// - exit(0)：命令行模式执行完后直接退出，不进入 GUI 主循环。
// - MainActor.assumeIsolated：告诉编译器当前在主线程上下文，可以安全访问 UI 对象。
// - NSApplication.shared / app.run()：AppKit 应用主对象和事件循环入口。
// 命令行调试入口：`Seeubot --stats` 只采集一次并输出 JSON，不启动 UI。
// 系统 API（行级）：CommandLine.arguments 读取命令行启动参数。
if CommandLine.arguments.contains("--stats") {
    let stats = SessionCollector().collect()
    // 系统 API（行级）：JSONEncoder 把 Swift Codable 数据编码成 JSON。
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let d = try? enc.encode(stats), let s = String(data: d, encoding: .utf8) {
        print(s)
    }
    exit(0)
}

// Top-level code runs on the main thread; assert main-actor isolation so we can
// touch the @MainActor app objects without concurrency warnings.
// 系统 API（行级）：MainActor.assumeIsolated 告诉编译器当前代码在主线程上下文。
MainActor.assumeIsolated {
    // UI 预览入口：`Seeubot --render <dir>` 离屏渲染截图，方便调样式。
// 系统 API（行级）：CommandLine.arguments 读取命令行启动参数。
if let i = CommandLine.arguments.firstIndex(of: "--render") {
    // 系统 API（行级）：CommandLine.arguments 读取命令行启动参数。
    let dir = i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : "."
    let stats = SessionCollector().collect()
    // 系统 API（行级）：MainActor.assumeIsolated 告诉编译器当前代码在主线程上下文。
    MainActor.assumeIsolated {
        // 系统 API（行级）：NSScreen 提供当前屏幕列表和主屏信息。
        let metrics = NotchMetrics.measure(NSScreen.main)
        RenderPreview.run(stats: stats, metrics: metrics, dir: dir)
    }
    exit(0)
}

// 系统 API（行级）：NSApplication.shared 是 AppKit 的全局应用对象，用来启动 macOS 事件循环。
let app = NSApplication.shared
    let delegate = AppDelegate()
    // 系统 API（行级）：AppKit 用 delegate 接收应用生命周期回调。
    app.delegate = delegate
    // `NSApplication.delegate` is weak — keep a strong reference alive for the
    // lifetime of the process (run() blocks here, retaining `delegate`).
    // 系统 API（行级）：app.run() 进入 macOS 主事件循环，窗口和菜单开始响应事件。
    app.run()
}
