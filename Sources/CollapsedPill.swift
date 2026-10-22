import SwiftUI

// 系统 API 速览：
// - HStack：横向摆放小机器人、working 指标、idle 指标。
// - .frame：限制胶囊内容高度。
// - .clipped：裁掉机器人的星星画布溢出部分，避免挤占右侧指标。
/// Collapsed content for the **hanging** mode: mascot + working/idle counts in a
/// single row that fits within the notch width and covers no menu-bar tools.
struct CollapsedPill: View {
    var stats: DashStats
    var metrics: NotchMetrics

    private var mood: Mood { Mood.from(stats) }

    var body: some View {
        HStack(spacing: 16) {
            MascotView(mood: mood, size: 23)
                .frame(width: 25)
                // 让宽大的星星画布不挤占右侧指标的空间。
                .clipped()
            LiveMetric(icon: "bolt.fill", value: stats.totalWorking,
                       color: Palette.working, pulse: stats.totalWorking > 0)
            LiveMetric(icon: "moon.zzz.fill", value: stats.totalIdle, color: Palette.idle)
        }
        .frame(height: Dim.pillHeight)
    }
}
