//药丸里放什么：左边一个静止的机器人，右边「几个在忙 / 几个空闲」
//药丸指的是有刘海下悬挂的形态
//有刘海也可以是长条，在后期菜单栏实现中可选择
import SwiftUI
struct CollapsedPill: View {
    var stats: DashStats
    var metrics: NotchMetrics
    private var mood: Mood { Mood.from(stats) }
    var body: some View {
        HStack(spacing: 16) {
            MascotView(mood: mood, size: 23)
                .frame(width: 25)
                .clipped()
            LiveMetric(icon: "bolt.fill", value: stats.totalWorking,
                       color: Palette.working, pulse: stats.totalWorking > 0)
            LiveMetric(icon: "moon.zzz.fill", value: stats.totalIdle, color: Palette.idle)
        }
        .frame(height: Dim.pillHeight)
    }
}