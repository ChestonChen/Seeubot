import AppKit

// Headless mode: print the collected stats as JSON and exit. Handy for debugging.
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
    // Off-screen render mode: `--render <dir>` writes PNGs of the widget and exits.
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
