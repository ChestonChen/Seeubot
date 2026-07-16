import SwiftUI

// 系统 API 速览：
// - View / body：SwiftUI 组件协议和声明式 UI 入口。
// - VStack / HStack / Spacer：纵向、横向和弹性空白布局。
// - Text / Image(systemName:)：文字和 SF Symbols 系统图标。
// - ForEach：按数组动态渲染多行工具统计或 session chip。
// - GeometryReader：读取布局宽度，用于 FlowLayout 或尺寸测量。
// - RoundedRectangle / Capsule / Ellipse：SwiftUI 内置形状。
// - LinearGradient / AngularGradient：渐变填充，用于毛玻璃和光晕。
// - TimelineView：按动画帧更新时间，用于旋转光晕。
// - .font / .foregroundStyle / .padding / .frame：常见 UI 样式修饰符。
/// 鼠标 hover 后展开的 dashboard。这里只做展示，不做采集逻辑。
/// 它接收 `DashStats`，把 sessions、working/idle 和 token 画成卡片。
// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct DashboardBody: View {
    var stats: DashStats
    var loaded: Bool
    var mode: WidgetMode = .hanging
    var hasNotch: Bool = true
    var updateTag: String? = nil
    var onToggleMode: () -> Void = {}
    var onMenu: () -> Void = {}

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        // 系统 API（行级）：VStack 纵向排列子视图。
        VStack(alignment: .leading, spacing: 10) {
            header

            // 顶部三个统计块：当前 live session、正在工作、空闲。
            // 系统 API（行级）：HStack 横向排列子视图。
            HStack(spacing: 8) {
                // 系统 API（行级）：.opacity 设置透明度。
                StatTile(title: "Sessions", value: stats.totalLive, accent: Palette.ink.opacity(0.9), glyph: "◎")
                StatTile(title: "Working", value: stats.totalWorking, accent: Palette.working,
                         glyph: "⚡", pulse: stats.totalWorking > 0)
                StatTile(title: "Idle", value: stats.totalIdle, accent: Palette.idle, glyph: "☾")
            }

            tokenHero

            // 每个 agent 的聚合行：Claude / Codex / Cursor 动态遍历，不再写死。
            // 系统 API（行级）：VStack 纵向排列子视图。
            VStack(spacing: 10) {
                // 系统 API（行级）：ForEach 根据集合动态生成多个 SwiftUI 子视图。
                ForEach(stats.perTool, id: \.tool.id) { stat in
                    ToolRow(stat: stat, grandTotal: stats.tokensAllTime.total)
                }
            }
            // 系统 API（行级）：.padding 设置内边距。
            .padding(.top, 2)

            liveSessions

            footer
        }
        // 系统 API（行级）：.padding 设置内边距。
        .padding(13)
        // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
        .frame(width: Dim.cardWidth, alignment: .leading)
    }

    // MARK: Header

    /// Dashboard 顶部：机器人、标题、更新提示、形态切换和菜单。
    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private var header: some View {
        // 系统 API（行级）：HStack 横向排列子视图。
        HStack(alignment: .center, spacing: 10) {
            MascotView(mood: Mood.from(stats), size: 34)
            // 系统 API（行级）：VStack 纵向排列子视图。
            VStack(alignment: .leading, spacing: 1) {
                // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                Text("Seeubot")
                    // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
                    .font(Typo.rounded(17, .heavy))
                    // 系统 API（行级）：.foregroundStyle 设置前景颜色/渐变样式。
                    .foregroundStyle(Palette.ink)
                // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                Text("AI SESSION MONITOR")
                    // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
                    .font(Typo.rounded(9, .medium))
                    // 系统 API（行级）：.foregroundStyle 设置前景颜色/渐变样式。
                    .foregroundStyle(Palette.inkFaint)
                    // 系统 API（行级）：.tracking 调整字间距。
                    .tracking(1.5)
            }
            // 系统 API（行级）：Spacer 是 SwiftUI 弹性空白，占据剩余空间。
            Spacer(minLength: 6)
            if updateTag != nil { updateBadge }
            if hasNotch { modeToggle }
            menuButton
        }
    }

    /// 点击切换收起态形态（hanging ⇄ sides），选择会存在 `StatsStore.mode` 里。
    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private var modeToggle: some View {
        // 系统 API（行级）：HStack 横向排列子视图。
        HStack(spacing: 4) {
            // 系统 API（行级）：Image(systemName:) 显示 SF Symbols 系统图标。
            Image(systemName: mode.icon).font(.system(size: 9, weight: .bold))
            // 系统 API（行级）：Text 是 SwiftUI 文本组件。
            Text(mode.label).font(Typo.rounded(10, .semibold))
        }
        // 系统 API（行级）：.foregroundStyle 设置前景颜色/渐变样式。
        .foregroundStyle(Palette.inkDim)
        // 系统 API（行级）：.padding 设置内边距。
        .padding(.horizontal, 8).padding(.vertical, 4)
        // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
        .background(Capsule().fill(Color.white.opacity(0.06))
            // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)))
        // 系统 API（行级）：Capsule 是 SwiftUI 胶囊形状。
        .contentShape(Capsule())
        // 系统 API（行级）：.onTapGesture 注册点击手势回调。
        .onTapGesture { onToggleMode() }
        // 系统 API（行级）：.help 设置 macOS hover 提示文案。
        .help("切换形态：下挂 / 两侧")
    }

    /// The "⋯" control button — always-visible, notch-proof way to reach show/hide,
    /// switch form, check updates and **quit**.
    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private var menuButton: some View {
        // 系统 API（行级）：Image(systemName:) 显示 SF Symbols 系统图标。
        Image(systemName: "ellipsis.circle.fill")
            // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
            .font(.system(size: 17))
            // 系统 API（行级）：.foregroundStyle 设置前景颜色/渐变样式。
            .foregroundStyle(Palette.inkDim)
            // 系统 API（行级）：Circle 是 SwiftUI 圆形形状。
            .contentShape(Circle())
            // 系统 API（行级）：.onTapGesture 注册点击手势回调。
            .onTapGesture { onMenu() }
            // 系统 API（行级）：.help 设置 macOS hover 提示文案。
            .help("菜单 · 切换 / 隐藏 / 退出")
    }

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private var updateBadge: some View {
        // 系统 API（行级）：HStack 横向排列子视图。
        HStack(spacing: 3) {
            // 系统 API（行级）：Image(systemName:) 显示 SF Symbols 系统图标。
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 9, weight: .bold))
            // 系统 API（行级）：Text 是 SwiftUI 文本组件。
            Text("Update").font(Typo.rounded(9, .bold))
        }
        // 系统 API（行级）：.foregroundStyle 设置前景颜色/渐变样式。
        .foregroundStyle(Palette.working)
        // 系统 API（行级）：.padding 设置内边距。
        .padding(.horizontal, 7).padding(.vertical, 4)
        // 系统 API（行级）：Capsule 是 SwiftUI 胶囊形状。
        .background(Capsule().fill(Palette.working.opacity(0.16)))
        // 系统 API（行级）：Capsule 是 SwiftUI 胶囊形状。
        .contentShape(Capsule())
        // 系统 API（行级）：.onTapGesture 注册点击手势回调。
        .onTapGesture { onMenu() }
        // 系统 API（行级）：.help 设置 macOS hover 提示文案。
        .help("Update available \(updateTag ?? "")")
    }

    // MARK: Token hero

    /// 中间最大的 token 卡片：总 token、output token、今日 token 和分段条都在这里。
    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private var tokenHero: some View {
        // 系统 API（行级）：VStack 纵向排列子视图。
        VStack(alignment: .leading, spacing: 10) {
            // 系统 API（行级）：HStack 横向排列子视图。
            HStack(alignment: .bottom) {
                // 系统 API（行级）：VStack 纵向排列子视图。
                VStack(alignment: .leading, spacing: 2) {
                    // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                    Text("TOTAL TOKENS")
                        // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
                        .font(Typo.rounded(10, .semibold))
                        // 系统 API（行级）：.foregroundStyle 设置前景颜色/渐变样式。
                        .foregroundStyle(Palette.inkDim).tracking(0.6)
                    AnimatedNumber(value: stats.tokensAllTime.total,
                                   font: Typo.rounded(34, .heavy), color: Palette.ink)
                }
                // 系统 API（行级）：Spacer 是 SwiftUI 弹性空白，占据剩余空间。
                Spacer()
                // 系统 API（行级）：VStack 纵向排列子视图。
                VStack(alignment: .trailing, spacing: 2) {
                    // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                    Text("OUTPUT").font(Typo.rounded(9, .semibold)).foregroundStyle(Palette.inkFaint)
                    AnimatedNumber(value: stats.tokensAllTime.output,
                                   font: Typo.rounded(16, .bold), color: Palette.tOutput)
                    // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                    Text("today \(Fmt.compact(stats.tokensToday.total))")
                        // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
                        .font(Typo.mono(9, .semibold)).foregroundStyle(Palette.inkFaint)
                }
            }
            SegmentedTokenBar(tb: stats.tokensAllTime)
        }
        // 系统 API（行级）：.padding 设置内边距。
        .padding(13)
        // 系统 API（行级）：.background 给视图添加背景层。
        .background(
            ZStack {
                // 系统 API（行级）：RoundedRectangle 是 SwiftUI 圆角矩形形状。
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    // 系统 API（行级）：.fill 用颜色或渐变填充形状。
                    .fill(.ultraThinMaterial)
                // 系统 API（行级）：RoundedRectangle 是 SwiftUI 圆角矩形形状。
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    // 系统 API（行级）：LinearGradient 创建线性渐变。
                    .fill(LinearGradient(
                        // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                RotatingAura(working: stats.totalWorking > 0)
                    // 系统 API（行级）：.opacity 设置透明度。
                    .opacity(stats.totalWorking > 0 ? 0.9 : 0.35)
            }
            // 系统 API（行级）：RoundedRectangle 是 SwiftUI 圆角矩形形状。
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        // 系统 API（行级）：.overlay 在视图上方叠加一层内容。
        .overlay(
            // 系统 API（行级）：RoundedRectangle 是 SwiftUI 圆角矩形形状。
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        // 系统 API（行级）：.overlay 在视图上方叠加一层内容。
        .overlay(
            // 系统 API（行级）：RoundedRectangle 是 SwiftUI 圆角矩形形状。
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                // 系统 API（行级）：.opacity 设置透明度。
                .stroke(Palette.working.opacity(stats.totalWorking > 0 ? 0.22 : 0.12), lineWidth: 1.2)
        )
    }

    // MARK: Live sessions

    /// 展示最近活跃的 session chip；为空时显示“安静状态”。
    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private var liveSessions: some View {
        // 系统 API（行级）：VStack 纵向排列子视图。
        VStack(alignment: .leading, spacing: 7) {
            // 系统 API（行级）：HStack 横向排列子视图。
            HStack(spacing: 5) {
                // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                Text("LIVE SESSIONS").font(Typo.rounded(11, .bold)).foregroundStyle(Palette.inkDim)
                // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                Text("\(stats.sessions.count)")
                    // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
                    .font(Typo.rounded(10, .bold)).foregroundStyle(Palette.inkFaint)
                // 系统 API（行级）：Spacer 是 SwiftUI 弹性空白，占据剩余空间。
                Spacer()
            }
            if stats.sessions.isEmpty {
                // 系统 API（行级）：HStack 横向排列子视图。
                HStack(spacing: 6) {
                    // 系统 API（行级）：Image(systemName:) 显示 SF Symbols 系统图标。
                    Image(systemName: "moon.stars.fill").foregroundStyle(Palette.idle)
                    // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                    Text("All quiet — grab a coffee ☕")
                        // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
                        .font(Typo.rounded(11, .medium)).foregroundStyle(Palette.inkDim)
                }
                // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                .frame(maxWidth: .infinity, alignment: .center)
                // 系统 API（行级）：.padding 设置内边距。
                .padding(.vertical, 8)
            } else {
                sessionFlow
            }
        }
    }

    /// session chip 使用自定义 FlowLayout，数量多时自动换行。
    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private var sessionFlow: some View {
        // Assigning to a local turns `layout { … }` into Dim.callAsFunction
        // (a bare `FlowLayout(args) { … }` is mis-parsed as an initializer call).
        let layout = FlowLayout(spacing: 6, lineSpacing: 6)
        return layout {
            // 系统 API（行级）：ForEach 根据集合动态生成多个 SwiftUI 子视图。
            ForEach(stats.sessions.prefix(8)) { s in
                SessionChip(session: s)
            }
            if stats.sessions.count > 8 {
                // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                Text("+\(stats.sessions.count - 8)")
                    // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
                    .font(Typo.rounded(11, .bold)).foregroundStyle(Palette.inkFaint)
                    // 系统 API（行级）：.padding 设置内边距。
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
                    .background(Capsule().fill(Color.white.opacity(0.05)))
            }
        }
    }

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private var footer: some View {
        // 系统 API（行级）：HStack 横向排列子视图。
        HStack(spacing: 4) {
            // 系统 API（行级）：Text 是 SwiftUI 文本组件。
            Text("\(stats.sessionsAllTime) sessions all-time")
                // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
                .font(Typo.rounded(9, .medium)).foregroundStyle(Palette.inkFaint)
            // 系统 API（行级）：Spacer 是 SwiftUI 弹性空白，占据剩余空间。
            Spacer()
            // 系统 API（行级）：Text 是 SwiftUI 文本组件。
            Text(toolList)
                // 系统 API（行级）：.font 设置 SwiftUI 文本字体。
                .font(Typo.rounded(9, .medium)).foregroundStyle(Palette.inkFaint)
        }
    }

    /// footer 右侧的工具列表，来自 perTool，所以支持动态 agent。
    private var toolList: String {
        let names = stats.perTool.map { $0.tool.display }
        return names.isEmpty ? "No agents" : names.joined(separator: " · ")
    }
}

// MARK: - Rotating conic aura behind the token total

// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct RotatingAura: View {
    var working: Bool = false
    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        // working 时快速转，idle 时慢速转，避免无任务时浪费 GPU。
        // 系统 API（行级）：TimelineView 按时间刷新视图，常用于动画。
        TimelineView(.animation(minimumInterval: working ? 1.0 / 60 : 1.0 / 6, paused: false)) { tl in
            let a = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) / 8
            // 系统 API（行级）：Ellipse 是 SwiftUI 椭圆形状。
            Ellipse()
                // 系统 API（行级）：AngularGradient 创建角向渐变，适合旋转光晕。
                .fill(AngularGradient(
                    // 系统 API（行级）：Gradient 定义渐变颜色序列。
                    gradient: Gradient(colors: [Palette.claude, Palette.codex, Palette.cursor, Palette.tCacheCreate, Palette.working, Palette.claude]),
                    center: .center,
                    angle: .degrees(a * 360)))
                // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                .frame(width: 220, height: 120)
                // 系统 API（行级）：.blur 给视图添加模糊效果。
                .blur(radius: 42)
                // 系统 API（行级）：.offset 在布局后偏移视图位置。
                .offset(x: 60, y: -10)
        }
    }
}
