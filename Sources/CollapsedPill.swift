import SwiftUI

// 系统 API 速览：
// - HStack：横向摆放小机器人、working 指标、idle 指标。
// - .frame：限制胶囊内容高度。
// - .clipped：裁掉跑道外的动画内容，避免机器人/拖尾溢出胶囊。
/// hanging 收起态：刘海下方的小胶囊。
/// 左侧是工作态会滑动的小机器人，右侧只放 working / idle 两个核心指标。
// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct CollapsedPill: View {
    var stats: DashStats
    var metrics: NotchMetrics

    private var mood: Mood { Mood.from(stats) }

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        // 系统 API（行级）：HStack 横向排列子视图。
        HStack(spacing: 12) {
            // active=true 时机器人在 96px 跑道内来回滑动，表达“agent 正在工作”。
            WorkingMascotRunway(mood: mood, active: stats.totalWorking > 0,
                                trackWidth: 96, height: Dim.pillHeight,
                                mascotSize: 23, restingEdge: .left)
                // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                .frame(width: 96, height: Dim.pillHeight)
                .clipped()
            LiveMetric(icon: "bolt.fill", value: stats.totalWorking,
                       color: Palette.working, pulse: stats.totalWorking > 0)
            LiveMetric(icon: "moon.zzz.fill", value: stats.totalIdle, color: Palette.idle)
        }
        // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
        .frame(height: Dim.pillHeight)
    }
}
