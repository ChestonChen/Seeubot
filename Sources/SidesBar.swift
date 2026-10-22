import SwiftUI

// 系统 API 速览：
// - Group：不额外生成布局容器，只用来在 if/else 中组织多种 View。
// - HStack：横向排布左右 bar 内容。
// - Color.clear：透明占位，这里用来给刘海区域留空。
// - .frame：固定左右区域和整体 bar 的宽高。
/// Collapsed CONTENT for the **sides / flat** form. The black bar background + clipping
/// is supplied by the shared morphing island in `NotchRootView`.
///
/// - Notched Macs: one bar spanning the notch — mascot on the left, a fixed-width empty
///   gap over the notch, live metrics on the right.
/// - Non-notched Macs: one flat continuous bar (no center gap) — mascot + metrics in a row.
// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct SidesBar: View {
    var stats: DashStats
    var metrics: NotchMetrics

    private var mood: Mood { Mood.from(stats) }
    private var barHeight: CGFloat { metrics.menuBarHeight }

    /// 根据屏幕是否有 notch 计算收起态总宽度。
    static func width(_ m: NotchMetrics) -> CGFloat {
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

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        // 系统 API（行级）：Group 只组织 View，不额外产生布局容器。
        Group {
            if metrics.notchWidth > 0 {
                // Notched: content flanks the empty notch gap.
                // 系统 API（行级）：HStack 横向排列子视图。
                HStack(spacing: 0) {
                    // 系统 API（行级）：HStack 横向排列子视图。
                    HStack(spacing: 0) { Spacer(minLength: 0); mascot }
                        // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                        .frame(width: Dim.barSideWidth)
                    // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
                    Color.clear.frame(width: metrics.notchWidth)
                    // 系统 API（行级）：HStack 横向排列子视图。
                    HStack(spacing: 0) {
                        // 系统 API（行级）：HStack 横向排列子视图。
                        HStack(spacing: 10) { working; idle }
                        // 系统 API（行级）：Spacer 是 SwiftUI 弹性空白，占据剩余空间。
                        Spacer(minLength: 0)
                    }
                    // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                    .frame(width: Dim.barSideWidth)
                }
            } else {
                // Non-notched: one continuous row, no gap.
                // 系统 API（行级）：HStack 横向排列子视图。
                HStack(spacing: 13) {
                    mascot
                    working
                    idle
                }
            }
        }
        // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
        .frame(width: SidesBar.width(metrics), height: barHeight)
    }
}
