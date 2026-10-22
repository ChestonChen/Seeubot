import SwiftUI

// 系统 API 速览：
// - HStack：横向摆放小机器人、working 指标、idle 指标。
// - .frame：限制胶囊内容高度。
// - .clipped：裁掉跑道外的动画内容，避免机器人/拖尾溢出胶囊。
/// Collapsed content for the **hanging** mode: mascot + working/idle counts in a
/// single row that fits within the notch width and covers no menu-bar tools.
// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct CollapsedPill: View {
    var stats: DashStats
    var metrics: NotchMetrics

    private var mood: Mood { Mood.from(stats) }

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        // 系统 API（行级）：HStack 横向排列子视图。
        HStack(spacing: 16) {
            MascotView(mood: mood, size: 23)
                // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                .frame(width: 25)
                // 让宽大的星星画布不挤占右侧指标的空间。
                .clipped()
            LiveMetric(icon: "bolt.fill", value: stats.totalWorking,
                       color: Palette.working, pulse: stats.totalWorking > 0)
            LiveMetric(icon: "moon.zzz.fill", value: stats.totalIdle, color: Palette.idle)
        }
        // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
        .frame(height: Dim.pillHeight)
    }
}
