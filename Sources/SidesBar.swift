import SwiftUI

// 系统 API 速览：
// - Group：不额外生成布局容器，只用来在 if/else 中组织多种 View。
// - HStack：横向排布左右 bar 内容。
// - Color.clear：透明占位，这里用来给刘海区域留空。
// - .frame：固定左右区域和整体 bar 的宽高。
/// sides / flat 收起态内容。外层黑色背景和裁剪由 `NotchRootView` 统一提供。
///
/// - 有刘海：中间留出 notch 空洞，左边机器人，右边 working/idle。
/// - 无刘海：没有中间空洞，直接变成顶部连续 bar。
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
    /// sides 形态下机器人靠右休息，working 时在左侧区域滑动。
    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private var mascot: some View {
        WorkingMascotRunway(mood: mood, active: stats.totalWorking > 0,
                            trackWidth: Dim.barSideWidth, height: barHeight,
                            // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
                            mascotSize: min(barHeight * 0.62, 21), restingEdge: .right)
    }

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        // 系统 API（行级）：Group 只组织 View，不额外产生布局容器。
        Group {
            if metrics.notchWidth > 0 {
                // Notched: content flanks the empty notch gap.
                // 系统 API（行级）：HStack 横向排列子视图。
                HStack(spacing: 0) {
                    mascot
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
                    WorkingMascotRunway(mood: mood, active: stats.totalWorking > 0,
                                        trackWidth: 56, height: barHeight,
                                        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
                                        mascotSize: min(barHeight * 0.62, 21), restingEdge: .right)
                    working
                    idle
                }
            }
        }
        // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
        .frame(width: SidesBar.width(metrics), height: barHeight)
    }
}
