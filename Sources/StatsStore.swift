import SwiftUI
import Combine
@MainActor
final class StatsStore: ObservableObject {//可被观察的对象协议
    //专门存界面状态的对象
    //@Published` —— 标记「这个属性变化时要通知订阅者」。没有它，改了值界面不会动
    @Published var metrics: NotchMetrics //界面几何尺寸
    @Published var stats: DashStats = .empty //记录最新面板快照
    @Published var loaded: Bool = false //是否采集过数据
    @Published var hover: Bool = false //鼠标是否在热区
    var onMenu: (() -> Void)?

    //用户一旦切换菜单展示状态就在本地写入mode，然后下次启动直接读本地mode加载
    @Published var mode: WidgetMode = WidgetMode(rawValue:
        UserDefaults.standard.string(forKey: "seeubot.mode") ?? "") ?? .hanging {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "seeubot.mode") }
    }
    //展示状态变化的辅助函数
    func toggleMode() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { mode = mode.next }
    }
    //nonisolated(unsafe)标记「这个属性不属于主线程，我会自己在后台队列用它」，防止类被mainactor握住放在主线程进行数据采集
    nonisolated(unsafe) private let collector = SessionCollector()
    //创建一条后台串行队列。`qos: .utility` = 低优先级，别和界面抢 CPU
    private let queue = DispatchQueue(label: "seeubot.collector", qos: .utility)
    nonisolated(unsafe) private var collecting = false
    private var timer: Timer?
    private let interval: TimeInterval //定时器与时间戳，控制采集间隔
    init(interval: TimeInterval = 3, metrics: NotchMetrics) {
        self.interval = interval
        self.metrics = metrics
        refresh()//构造的时候立刻采集刷新一次，避免面板是空的 丢到后台队列，内部执行collect然后回来赋值
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        t.tolerance = 0.1//允许系统把这个定时器的触发时间最多往后推 0.1 秒 ，为了合并定时器触发，省电
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    func updateMetrics(_ m: NotchMetrics) { metrics = m }//屏幕变化时更新几何

    nonisolated private func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.collecting { return }
            self.collecting = true //采集完改变状态，防止重复采集
            defer { self.collecting = false } //defer保证一定会被执行
            let snapshot = self.collector.collect() //获取快照
            Task { @MainActor in //切换主线程更新published 的快照
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                    self.stats = snapshot
                }
                self.loaded = true
            }
        }
    }
    //对象销毁时销毁计时器
    deinit { timer?.invalidate() }
}