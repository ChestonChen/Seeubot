//长条形态：有无刘海的布局

import SwiftUI
struct SidesBar: View {
    var stats: DashStats
    var metrics: NotchMetrics
    private var mood: Mood { Mood.from(stats) }
    private var barHeight: CGFloat { metrics.menuBarHeight }//高度与菜单持平
    static func width(_ m: NotchMetrics) -> CGFloat {//计算总宽度 热区判断要算
        m.notchWidth > 0 ? m.notchWidth + Dim.barSideWidth * 2 : Dim.flatBarWidth
    }
    private var working: LiveMetric {
        LiveMetric(icon: "bolt.fill", value: stats.totalWorking,
                   color: Palette.working, pulse: stats.totalWorking > 0)
    }
    private var idle: LiveMetric {
        LiveMetric(icon: "moon.zzz.fill", value: stats.totalIdle, color: Palette.idle)
    }
    private var mascot: some View {
        MascotView(mood: mood, size: min(barHeight * 0.62, 21)).frame(width: 25).clipped()
    }
    var body: some View {
        Group {//只组织视图、不产生布局容器，用来在 if/else 两个分支外面统一加修饰符
            if metrics.notchWidth > 0 {
                HStack(spacing: 0) {
                    HStack(spacing: 0) { Spacer(minLength: 0); mascot }
                        .frame(width: Dim.barSideWidth)
                    Color.clear.frame(width: metrics.notchWidth)
                    HStack(spacing: 0) {
                        HStack(spacing: 10) { working; idle }
                        Spacer(minLength: 0)
                    }
                    .frame(width: Dim.barSideWidth)
                }
            } else {
                HStack(spacing: 13) {
                    mascot
                    working
                    idle
                }
            }
        }
        .frame(width: SidesBar.width(metrics), height: barHeight)
    }
}