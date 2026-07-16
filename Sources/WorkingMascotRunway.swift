import SwiftUI

// 系统 API 速览：
// - @Environment(\.displayScale)：读取屏幕缩放比例，用于像素对齐。
// - TimelineView：按动画帧更新时间，驱动机器人滑动。
// - ZStack / VStack：叠放拖尾、机器人、小载具。
// - @ViewBuilder：让函数可以根据 switch 返回不同类型的 View。
// - ForEach：重复生成星星拖尾和速度线粒子。
// - Capsule / Circle：SwiftUI 内置形状，用来画小载具和粒子。
// - .position / .offset：控制粒子和机器人在跑道里的位置。
// - sin / cos：标准数学函数，用时间算平滑往返运动和方向。
/// 收起态专用的小机器人跑道。
/// 有 working agent 时，机器人会在可用空间内滑动，并随机切换拖尾/速度线效果。
// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct WorkingMascotRunway: View {
    // 系统 API（行级）：@Environment 从 SwiftUI 环境读取系统/上下文值。
    @Environment(\.displayScale) private var displayScale

    var mood: Mood
    var active: Bool
    var trackWidth: CGFloat
    var height: CGFloat
    var mascotSize: CGFloat
    var restingEdge: RestingEdge = .left

    enum RestingEdge {
        case left
        case right
    }

    // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
    private var mascotWidth: CGFloat { max(25, mascotSize * 1.6) }

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        // 系统 API（行级）：TimelineView 按时间刷新视图，常用于动画。
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !active)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
            let travel = max(0, trackWidth - mascotWidth)
            let motionSpeed = 1.35
            // phase 在 0...1 之间来回变化，决定机器人当前在跑道中的位置。
            // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
            let phase = active ? (0.5 + 0.5 * sin(t * motionSpeed)) : restingPhase
            let x = pixelAligned(CGFloat(phase) * travel)
            // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
            let y = pixelAligned(active ? CGFloat(sin(t * 2.9)) * 1.1 : 0)
            // direction 用来决定拖尾方向：向右走时拖尾在左，向左走时拖尾在右。
            // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
            let direction: CGFloat = cos(t * motionSpeed) >= 0 ? 1 : -1
            let action = active ? WorkPropAction.pick(t) : .none

            // 系统 API（行级）：ZStack 叠放子视图。
            ZStack(alignment: .leading) {
                if active {
                    propLayer(action: action, botX: x, phase: phase, direction: direction, t: t)
                }

                // 系统 API（行级）：ZStack 叠放子视图。
                ZStack(alignment: .bottom) {
                    MascotView(mood: mood, size: mascotSize)
                        // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                        .frame(width: mascotWidth, height: height)
                        .clipped()

                    if active {
                        vehicleLayer(action: action, t: t)
                    }
                }
                // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                .frame(width: mascotWidth, height: height)
                .compositingGroup()
                // 系统 API（行级）：.offset 在布局后偏移视图位置。
                .offset(x: x, y: y)
            }
            // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
            .frame(width: trackWidth, height: height, alignment: .leading)
        }
    }

    private var restingPhase: Double {
        switch restingEdge {
        case .left: return 0
        case .right: return 1
        }
    }

    /// 把偏移对齐到真实屏幕像素，减少 SwiftUI 动画过程中的抖动/锯齿感。
    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        guard displayScale > 0 else { return value }
        return (value * displayScale).rounded() / displayScale
    }

    @ViewBuilder
    /// 机器人身后的工作特效层：星星拖尾或速度线。
    private func propLayer(action: WorkPropAction, botX: CGFloat, phase: Double,
                           // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
                           direction: CGFloat, t: Double) -> some View {
        switch action {
        case .sparkTrail:
            sparkTrail(botX: botX, phase: phase, direction: direction, t: t)
        case .speedLines:
            speedParticles(botX: botX, phase: phase, direction: direction, t: t)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    /// 机器人底部的小载具效果，和拖尾类型保持一致。
    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private func vehicleLayer(action: WorkPropAction, t: Double) -> some View {
        switch action {
        case .sparkTrail:
            tinyHoverPad(t: t)
        case .speedLines:
            tinyRocketSkid(t: t)
        case .none:
            EmptyView()
        }
    }

    /// 星星拖尾：根据 direction 放在机器人运动方向的反侧。
    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private func sparkTrail(botX: CGFloat, phase: Double, direction: CGFloat, t: Double) -> some View {
        let fade = CGFloat(edgeFade(phase))
        let anchorX = botX + (direction > 0 ? mascotWidth * 0.20 : mascotWidth * 0.80)

        return ZStack {
            // 系统 API（行级）：ForEach 根据集合动态生成多个 SwiftUI 子视图。
            ForEach(0..<5, id: \.self) { i in
                let lag = CGFloat(i) * 6.5 * fade
                // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
                let pulse = 0.55 + 0.45 * sin(t * 4.2 + Double(i))
                let x = clamped(anchorX - direction * lag, min: 4, max: trackWidth - 4)
                // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
                let y = height * (0.38 + 0.05 * CGFloat(sin(t * 2 + Double(i))))

                sparkleDot(size: 2.6 + CGFloat(pulse) * 1.8)
                    // 系统 API（行级）：.foregroundStyle 设置前景颜色/渐变样式。
                    .foregroundStyle(Palette.working.opacity(Double(fade) * (0.25 + 0.55 * pulse)))
                    // 系统 API（行级）：.position 用绝对坐标放置视图。
                    .position(x: x, y: y)
            }
        }
    }

    /// 速度线：和星星拖尾同样遵守“运动方向反侧 + 边缘淡出”。
    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private func speedParticles(botX: CGFloat, phase: Double, direction: CGFloat, t: Double) -> some View {
        let fade = CGFloat(edgeFade(phase))
        let anchorX = botX + (direction > 0 ? mascotWidth * 0.16 : mascotWidth * 0.84)

        return ZStack {
            // 系统 API（行级）：ForEach 根据集合动态生成多个 SwiftUI 子视图。
            ForEach(0..<4, id: \.self) { i in
                // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
                let pulse = 0.5 + 0.5 * sin(t * 5.2 + Double(i) * 0.7)
                let lag = CGFloat(i) * 6 * fade
                let x = clamped(anchorX - direction * lag, min: 4, max: trackWidth - 4)
                // 系统 API（行级）：Capsule 是 SwiftUI 胶囊形状。
                Capsule()
                    // 系统 API（行级）：.opacity 设置透明度。
                    .fill(Palette.working.opacity(0.22 + 0.38 * pulse))
                    // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                    .frame(width: 4.5, height: 2.4)
                    // 系统 API（行级）：.scaleEffect 缩放视图。
                    .scaleEffect(0.65 + CGFloat(pulse) * 0.35)
                    // 系统 API（行级）：.opacity 设置透明度。
                    .opacity(Double(fade))
                    // 系统 API（行级）：.position 用绝对坐标放置视图。
                    .position(x: x, y: height * (0.42 + CGFloat(i % 3) * 0.07))
            }
        }
    }

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private func sparkleDot(size: CGFloat) -> some View {
        ZStack {
            // 系统 API（行级）：Capsule 是 SwiftUI 胶囊形状。
            Capsule().frame(width: size * 0.42, height: size)
            // 系统 API（行级）：Capsule 是 SwiftUI 胶囊形状。
            Capsule().frame(width: size, height: size * 0.42)
        }
    }

    /// 靠近跑道两端时让拖尾逐渐消失，避免粒子挤到边缘。
    private func edgeFade(_ phase: Double) -> Double {
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        min(1, max(0, min(phase, 1 - phase) / 0.16))
    }

    private func clamped(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        Swift.min(Swift.max(value, minValue), maxValue)
    }

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private func tinyHoverPad(t: Double) -> some View {
        // 系统 API（行级）：VStack 纵向排列子视图。
        VStack(spacing: 0) {
            // 系统 API（行级）：Spacer 是 SwiftUI 弹性空白，占据剩余空间。
            Spacer(minLength: 0)
            // 系统 API（行级）：Capsule 是 SwiftUI 胶囊形状。
            Capsule()
                // 系统 API（行级）：.opacity 设置透明度。
                .fill(Palette.idle.opacity(0.72))
                // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                .frame(width: 21, height: 4)
                // 系统 API（行级）：.shadow 给视图添加阴影。
                .shadow(color: Palette.idle.opacity(0.45), radius: 3, y: 1)
                // 系统 API（行级）：.offset 在布局后偏移视图位置。
                .offset(y: -2 + CGFloat(sin(t * 5)) * 0.4)
        }
    }

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private func tinyRocketSkid(t: Double) -> some View {
        // 系统 API（行级）：VStack 纵向排列子视图。
        VStack(spacing: 0) {
            // 系统 API（行级）：Spacer 是 SwiftUI 弹性空白，占据剩余空间。
            Spacer(minLength: 0)
            // 系统 API（行级）：Capsule 是 SwiftUI 胶囊形状。
            Capsule()
                // 系统 API（行级）：.opacity 设置透明度。
                .fill(Palette.working.opacity(0.78))
                // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                .frame(width: 20, height: 5)
                // 系统 API（行级）：.overlay 在视图上方叠加一层内容。
                .overlay(alignment: .leading) {
                    // 系统 API（行级）：Circle 是 SwiftUI 圆形形状。
                    Circle()
                        // 系统 API（行级）：.opacity 设置透明度。
                        .fill(Color(red: 1.0, green: 0.78, blue: 0.35).opacity(0.85))
                        // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                        .frame(width: 5, height: 5)
                        // 系统 API（行级）：.offset 在布局后偏移视图位置。
                        .offset(x: -2 - CGFloat(sin(t * 8)) * 1.2)
                }
                // 系统 API（行级）：.offset 在布局后偏移视图位置。
                .offset(y: -2)
        }
    }
}

private enum WorkPropAction {
    case none
    case sparkTrail
    case speedLines

    /// 每 5.2 秒确定性随机一次。用 hash 而不是真正随机，避免每帧闪烁。
    static func pick(_ t: Double) -> WorkPropAction {
        let slotLength = 5.2
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        let slot = floor(t / slotLength)
        let r = hash01(slot)
        return r < 0.5 ? .sparkTrail : .speedLines
    }

    private static func hash01(_ n: Double) -> Double {
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        let v = sin(n * 12.9898) * 43758.5453
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        return v - floor(v)
    }
}
