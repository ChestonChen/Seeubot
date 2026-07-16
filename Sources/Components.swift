import SwiftUI

// 系统 API 速览：
// - Text / Image(systemName:)：文字和系统图标。
// - TimelineView：周期性驱动呼吸点动画。
// - Circle / Capsule / RoundedRectangle：内置形状，用于点、胶囊和卡片。
// - GeometryReader：读取可用宽度，计算 token 分段条每段长度。
// - ForEach：循环生成 token legend、分段条等重复 UI。
// - .contentTransition(.numericText)：数字变化时使用系统数字滚动动画。
// - .monospacedDigit：让数字等宽，避免刷新时左右抖动。
// - .ultraThinMaterial：系统毛玻璃材质。
// - .background / .overlay / .shadow：常见 SwiftUI 外观叠加修饰符。
// MARK: - Rolling number

/// A compact-formatted number that animates its digits when it changes.
// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct AnimatedNumber: View {
    var value: Int
    var font: Font
    var color: Color = Palette.ink

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        // 系统 API（行级）：Text 是 SwiftUI 文本组件。
        Text(Fmt.compact(value))
            // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
            .font(font)
            // 系统 API（行级）：.foregroundStyle 设置前景颜色/渐变样式。
            .foregroundStyle(color)
            // 系统 API（行级）：.monospacedDigit 让数字等宽，避免变化时抖动。
            .monospacedDigit()
            // 系统 API（行级）：.contentTransition 设置内容变化动画。
            .contentTransition(.numericText(value: Double(value)))
            // 系统 API（行级）：.animation 绑定状态变化时的动画。
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: value)
    }
}

// MARK: - Pulsing state dot

// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct PulseDot: View {
    var color: Color
    var active: Bool
    var size: CGFloat = 8

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        // 系统 API（行级）：TimelineView 按时间刷新视图，常用于动画。
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let phase = active ? (t.truncatingRemainder(dividingBy: 1.6) / 1.6) : 0
            ZStack {
                if active {
                    // 系统 API（行级）：Circle 是 SwiftUI 圆形形状。
                    Circle()
                        // 系统 API（行级）：.stroke 给形状描边。
                        .stroke(color, lineWidth: 1.5)
                        // 系统 API（行级）：.scaleEffect 缩放视图。
                        .scaleEffect(1 + CGFloat(phase) * 1.7)
                        // 系统 API（行级）：.opacity 设置透明度。
                        .opacity((1 - phase) * 0.7)
                }
                // 系统 API（行级）：Circle 是 SwiftUI 圆形形状。
                Circle()
                    // 系统 API（行级）：.fill 用颜色或渐变填充形状。
                    .fill(color)
                    // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                    .frame(width: size, height: size)
                    // 系统 API（行级）：.shadow 给视图添加阴影。
                    .shadow(color: active ? color.opacity(0.8) : .clear, radius: active ? 4 : 0)
                    // 系统 API（行级）：.scaleEffect 缩放视图。
                    .scaleEffect(active ? 1 + 0.12 * CGFloat(sin(t * 4)) : 1)
            }
            // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
            .frame(width: size * 3, height: size * 3)
        }
        // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
        .frame(width: size, height: size)
    }
}

/// A compact solid dot that gently breathes (subtle glow) when active — no large
/// expanding ring, so it stays tidy in the tight collapsed pill.
// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct GlowDot: View {
    var color: Color
    var active: Bool
    var size: CGFloat = 7

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        // 系统 API（行级）：TimelineView 按时间刷新视图，常用于动画。
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !active)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
            let s = active ? 1 + 0.12 * CGFloat(sin(t * 4)) : 1
            // 系统 API（行级）：Circle 是 SwiftUI 圆形形状。
            Circle()
                // 系统 API（行级）：.fill 用颜色或渐变填充形状。
                .fill(color)
                // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                .frame(width: size, height: size)
                // 系统 API（行级）：.scaleEffect 缩放视图。
                .scaleEffect(s)
                // 系统 API（行级）：.shadow 给视图添加阴影。
                .shadow(color: active ? color.opacity(0.85) : .clear, radius: active ? 3.5 : 0)
        }
        // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
        .frame(width: size, height: size)
    }
}

/// One live metric shown in the collapsed widget: a glyph/dot + animated count.
// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct LiveMetric: View {
    var icon: String
    var value: Int
    var color: Color
    var pulse: Bool = false

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        // 系统 API（行级）：HStack 横向排列子视图。
        HStack(spacing: 4) {
            if pulse {
                GlowDot(color: color, active: true, size: 7)
            } else {
                // 系统 API（行级）：Image(systemName:) 显示 SF Symbols 系统图标。
                Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            }
            AnimatedNumber(value: value, font: Typo.rounded(14, .bold), color: color)
        }
    }
}

// MARK: - Glass surfaces

// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct GlassPanelBackground: View {
    var cornerRadius: CGFloat
    var accent: Color = Palette.ink
    var accentOpacity: Double = 0.18

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        // 系统 API（行级）：RoundedRectangle 是 SwiftUI 圆角矩形形状。
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            // 系统 API（行级）：.fill 用颜色或渐变填充形状。
            .fill(.ultraThinMaterial)
            // 系统 API（行级）：.overlay 在视图上方叠加一层内容。
            .overlay(
                // 系统 API（行级）：RoundedRectangle 是 SwiftUI 圆角矩形形状。
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    // 系统 API（行级）：LinearGradient 创建线性渐变。
                    .fill(LinearGradient(
                        // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
                        colors: [Color.white.opacity(0.13), Color.white.opacity(0.035)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            )
            // 系统 API（行级）：.overlay 在视图上方叠加一层内容。
            .overlay(
                // 系统 API（行级）：RoundedRectangle 是 SwiftUI 圆角矩形形状。
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            // 系统 API（行级）：.overlay 在视图上方叠加一层内容。
            .overlay(
                // 系统 API（行级）：RoundedRectangle 是 SwiftUI 圆角矩形形状。
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    // 系统 API（行级）：.opacity 设置透明度。
                    .stroke(accent.opacity(accentOpacity), lineWidth: 1.2)
            )
            // 系统 API（行级）：.shadow 给视图添加阴影。
            .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 5)
    }
}

// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct GlassCapsuleBackground: View {
    var accent: Color

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        // 系统 API（行级）：Capsule 是 SwiftUI 胶囊形状。
        Capsule()
            // 系统 API（行级）：.fill 用颜色或渐变填充形状。
            .fill(.ultraThinMaterial)
            // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
            .overlay(Capsule().fill(Color.white.opacity(0.08)))
            // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
            // 系统 API（行级）：Capsule 是 SwiftUI 胶囊形状。
            .overlay(Capsule().stroke(accent.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Stat tile

// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct StatTile: View {
    var title: String
    var value: Int
    var accent: Color
    var glyph: String
    var pulse: Bool = false

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        // 系统 API（行级）：VStack 纵向排列子视图。
        VStack(alignment: .leading, spacing: 4) {
            // 系统 API（行级）：HStack 横向排列子视图。
            HStack(spacing: 5) {
                if pulse {
                    PulseDot(color: accent, active: true, size: 6)
                } else {
                    // 系统 API（行级）：Circle 是 SwiftUI 圆形形状。
                    Circle().fill(accent).frame(width: 6, height: 6)
                }
                // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                Text(title)
                    // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
                    .font(Typo.rounded(10, .semibold))
                    // 系统 API（行级）：.foregroundStyle 设置前景颜色/渐变样式。
                    .foregroundStyle(Palette.inkDim)
                    // 系统 API（行级）：.textCase 改变文本大小写显示。
                    .textCase(.uppercase)
                    // 系统 API（行级）：.tracking 调整字间距。
                    .tracking(0.4)
            }
            // 系统 API（行级）：HStack 横向排列子视图。
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                AnimatedNumber(value: value, font: Typo.rounded(26, .bold), color: Palette.ink)
                // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                Text(glyph).font(Typo.rounded(12, .semibold)).foregroundStyle(accent)
            }
        }
        // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
        .frame(maxWidth: .infinity, alignment: .leading)
        // 系统 API（行级）：.padding 设置内边距。
        .padding(.vertical, 10)
        // 系统 API（行级）：.padding 设置内边距。
        .padding(.horizontal, 12)
        // 系统 API（行级）：.background 给视图添加背景层。
        .background(GlassPanelBackground(cornerRadius: 14, accent: accent, accentOpacity: 0.24))
    }
}

// MARK: - Segmented token bar

// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct SegmentedTokenBar: View {
    var tb: TokenBreakdown
    var height: CGFloat = 12

    private var segments: [(Color, Int, String)] {
        [(Palette.tOutput, tb.output, "Output"),
         (Palette.tInput, tb.inputFresh, "Input"),
         (Palette.tCacheCreate, tb.cacheCreate, "Cache-W"),
         (Palette.tCacheRead, tb.cacheRead, "Cache-R")]
    }

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        let total = max(1, tb.total)
        // 系统 API（行级）：VStack 纵向排列子视图。
        VStack(alignment: .leading, spacing: 7) {
            // 系统 API（行级）：GeometryReader 读取父容器给出的尺寸。
            GeometryReader { geo in
                // 系统 API（行级）：HStack 横向排列子视图。
                HStack(spacing: 1.5) {
                    // 系统 API（行级）：ForEach 根据集合动态生成多个 SwiftUI 子视图。
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        // 系统 API（行级）：Capsule 是 SwiftUI 胶囊形状。
                        Capsule()
                            // 系统 API（行级）：.fill 用颜色或渐变填充形状。
                            .fill(seg.0)
                            // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                            .frame(width: max(seg.1 > 0 ? 3 : 0,
                                              geo.size.width * CGFloat(seg.1) / CGFloat(total)))
                    }
                }
                // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                .frame(height: height)
                // 系统 API（行级）：Capsule 是 SwiftUI 胶囊形状。
                .clipShape(Capsule())
            }
            // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
            .frame(height: height)

            // legend
            // 系统 API（行级）：HStack 横向排列子视图。
            HStack(spacing: 10) {
                // 系统 API（行级）：ForEach 根据集合动态生成多个 SwiftUI 子视图。
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    // 系统 API（行级）：HStack 横向排列子视图。
                    HStack(spacing: 3) {
                        // 系统 API（行级）：Circle 是 SwiftUI 圆形形状。
                        Circle().fill(seg.0).frame(width: 6, height: 6)
                        // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                        Text(seg.2).font(Typo.rounded(9, .medium)).foregroundStyle(Palette.inkDim)
                        // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                        Text(Fmt.compact(seg.1)).font(Typo.mono(9, .semibold)).foregroundStyle(Palette.inkFaint)
                    }
                }
                // 系统 API（行级）：Spacer 是 SwiftUI 弹性空白，占据剩余空间。
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Per-tool row

// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct ToolRow: View {
    var stat: ToolStat
    var grandTotal: Int

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        let accent = Palette.tool(stat.tool)
        // 系统 API（行级）：HStack 横向排列子视图。
        HStack(spacing: 10) {
            // badge
            ZStack {
                // 系统 API（行级）：RoundedRectangle 是 SwiftUI 圆角矩形形状。
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    // 系统 API（行级）：.fill 用颜色或渐变填充形状。
                    .fill(Palette.gradient(stat.tool))
                    // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                    .frame(width: 30, height: 30)
                // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                Text(stat.tool.glyph).font(Typo.rounded(15, .bold)).foregroundStyle(.white)
            }
            // 系统 API（行级）：VStack 纵向排列子视图。
            VStack(alignment: .leading, spacing: 3) {
                // 系统 API（行级）：HStack 横向排列子视图。
                HStack(spacing: 6) {
                    // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                    Text(stat.tool.display).font(Typo.rounded(12, .bold)).foregroundStyle(Palette.ink)
                    if stat.working > 0 {
                        Label("\(stat.working)", systemImage: "bolt.fill")
                            // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
                            .font(Typo.rounded(9, .bold)).foregroundStyle(Palette.working)
                            .labelStyle(.titleAndIcon)
                    }
                    if stat.idle > 0 {
                        Label("\(stat.idle)", systemImage: "moon.zzz.fill")
                            // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
                            .font(Typo.rounded(9, .semibold)).foregroundStyle(Palette.idle)
                            .labelStyle(.titleAndIcon)
                    }
                    // 系统 API（行级）：Spacer 是 SwiftUI 弹性空白，占据剩余空间。
                    Spacer(minLength: 0)
                    // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                    Text(Fmt.compact(stat.tokensAllTime.total))
                        // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
                        .font(Typo.mono(11, .semibold)).foregroundStyle(accent)
                }
                // share bar
                // 系统 API（行级）：GeometryReader 读取父容器给出的尺寸。
                GeometryReader { geo in
                    // 系统 API（行级）：ZStack 叠放子视图。
                    ZStack(alignment: .leading) {
                        // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
                        Capsule().fill(Color.white.opacity(0.06))
                        // 系统 API（行级）：Capsule 是 SwiftUI 胶囊形状。
                        Capsule().fill(Palette.gradient(stat.tool))
                            // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                            .frame(width: geo.size.width *
                                   // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
                                   CGFloat(stat.tokensAllTime.total) / CGFloat(max(1, grandTotal)))
                    }
                }
                // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                .frame(height: 5)
            }
        }
    }
}

// MARK: - Live session chip

// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct SessionChip: View {
    var session: LiveSession

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        let working = session.state == .working
        // 系统 API（行级）：HStack 横向排列子视图。
        HStack(spacing: 6) {
            PulseDot(color: working ? Palette.working : Palette.idle, active: working, size: 6)
            // 系统 API（行级）：Text 是 SwiftUI 文本组件。
            Text(session.tool.glyph)
                // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
                .font(Typo.rounded(9, .bold))
                // 系统 API（行级）：.foregroundStyle 设置前景颜色/渐变样式。
                .foregroundStyle(Palette.tool(session.tool))
            // 系统 API（行级）：Text 是 SwiftUI 文本组件。
            Text(session.project)
                // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
                .font(Typo.rounded(11, .semibold))
                // 系统 API（行级）：.foregroundStyle 设置前景颜色/渐变样式。
                .foregroundStyle(working ? Palette.ink : Palette.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
                // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                .frame(maxWidth: 140, alignment: .leading)
        }
        // 系统 API（行级）：.padding 设置内边距。
        .padding(.horizontal, 9)
        // 系统 API（行级）：.padding 设置内边距。
        .padding(.vertical, 5)
        // 系统 API（行级）：.background 给视图添加背景层。
        .background(GlassCapsuleBackground(accent: working ? Palette.working : Palette.idle))
    }
}
