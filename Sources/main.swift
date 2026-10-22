import AppKit

// 系统 API 速览：
// - CommandLine.arguments：读取启动参数，比如 --stats / --render。
// - JSONEncoder：把 Swift 数据结构编码成 JSON 字符串，方便命令行调试。
// - exit(0)：命令行模式执行完后直接退出，不进入 GUI 主循环。
// - MainActor.assumeIsolated：告诉编译器当前在主线程上下文，可以安全访问 UI 对象。
// - NSApplication.shared / app.run()：AppKit 应用主对象和事件循环入口。
// 命令行调试入口：`Seeubot --stats` 只采集一次并输出 JSON，不启动 UI。
if CommandLine.arguments.contains("--stats") {
    let stats = SessionCollector().collect()
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let d = try? enc.encode(stats), let s = String(data: d, encoding: .utf8) {
        print(s)
    }
    exit(0)
}

// Top-level code runs on the main thread; assert main-actor isolation so we can
// touch the @MainActor app objects without concurrency warnings.
MainActor.assumeIsolated {
    // UI 预览入口：`Seeubot --render <dir>` 离屏渲染截图，方便调样式。
if let i = CommandLine.arguments.firstIndex(of: "--render") {
    let dir = i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : "."
    let stats = SessionCollector().collect()
    MainActor.assumeIsolated {
        let metrics = NotchMetrics.measure(NSScreen.main)
        RenderPreview.run(stats: stats, metrics: metrics, dir: dir)
    }
    exit(0)
}

let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // `NSApplication.delegate` is weak — keep a strong reference alive for the
    // lifetime of the process (run() blocks here, retaining `delegate`).
    app.run()
}
