import SwiftUI
import Combine

// 系统 API 速览：
// - ObservableObject：Combine/SwiftUI 的可观察对象协议，UI 可以订阅它。
// - @Published：属性变化时自动通知 SwiftUI 重新渲染。
// - UserDefaults：系统提供的本地轻量存储，用来记住用户选择的组件形态。
// - DispatchQueue：后台队列，避免采集文件/进程时阻塞主线程。
// - Timer.scheduledTimer：周期性触发刷新。
// - RunLoop.main.add：把 timer 加到主运行循环，让 UI 交互时也持续触发。
// - Task { @MainActor in ... }：采集完成后切回主线程更新 @Published 状态。
/// UI 的状态仓库：定时调用 `SessionCollector`，再把最新 `DashStats` 发布给 SwiftUI。
@MainActor
final class StatsStore: ObservableObject {
    @Published var stats: DashStats = .empty
    @Published var loaded: Bool = false
    @Published var metrics: NotchMetrics
    @Published var hover: Bool = false            // cursor is over the widget
    var onMenu: (() -> Void)?                     // in-widget "⋯" button → show control menu
    /// 用户选择的收起形态。写入 UserDefaults，所以重启后仍会记住。
    @Published var mode: WidgetMode = WidgetMode(rawValue:
        UserDefaults.standard.string(forKey: "seeubot.mode") ?? "") ?? .hanging {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "seeubot.mode") }
    }

    /// 展开态顶部按钮触发：在 hanging / sides 两种收起形态之间切换。
    func toggleMode() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { mode = mode.next }
    }

    // Only ever touched on `queue`, so accessing it off the main actor is safe.
    nonisolated(unsafe) private let collector = SessionCollector()
    private let queue = DispatchQueue(label: "seeubot.collector", qos: .utility)
    // Drop a tick if a previous collect() is still running (only touched on `queue`).
    nonisolated(unsafe) private var collecting = false
    private var timer: Timer?
    private let interval: TimeInterval

    init(interval: TimeInterval = 3, metrics: NotchMetrics) {
        self.interval = interval
        self.metrics = metrics
        // 启动时先采集一次，避免 UI 长时间停留在空态。
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func updateMetrics(_ m: NotchMetrics) { metrics = m }

    /// 真正的数据刷新入口。采集放在后台队列，避免扫描文件/进程时卡住 UI。
    nonisolated private func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            // Skip if the previous collect hasn't finished — prevents a serial-queue
            // backlog if a probe is ever slow.
            if self.collecting { return }
            self.collecting = true
            defer { self.collecting = false }
            let snapshot = self.collector.collect()
            Task { @MainActor in
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                    self.stats = snapshot
                }
                self.loaded = true
            }
        }
    }

    deinit { timer?.invalidate() }
}
