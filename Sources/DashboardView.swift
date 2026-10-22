import SwiftUI

// 系统 API 速览：
// - View / body：SwiftUI 组件协议和声明式 UI 入口。
// - VStack / HStack / Spacer：纵向、横向和弹性空白布局。
// - Text / Image(systemName:)：文字和 SF Symbols 系统图标。
// - ForEach：按数组动态渲染多行工具统计或 session chip。
// - GeometryReader：读取可用宽度，用于分段条和占比条。
// - RoundedRectangle / Capsule / Ellipse：SwiftUI 内置形状。
// - LinearGradient / AngularGradient：渐变填充，用于毛玻璃和光晕。
// - TimelineView：按动画帧更新时间，用于旋转光晕。
// - .font / .foregroundStyle / .padding / .frame：常见 UI 样式修饰符。
/// 鼠标 hover 后展开的 dashboard。这里只做展示，不做采集逻辑。
/// 它接收 `DashStats`，把 sessions、working/idle 和 token 画成卡片。
struct DashboardBody: View {
    var stats: DashStats
    var loaded: Bool
    var mode: WidgetMode = .hanging
    var hasNotch: Bool = true
    var updateTag: String? = nil
    var onToggleMode: () -> Void = {}
    var onMenu: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            // 顶部三个统计块：当前 live session、正在工作、空闲。
            HStack(spacing: 8) {
                StatTile(title: "Sessions", value: stats.totalLive, accent: Palette.ink.opacity(0.9), glyph: "◎")
                StatTile(title: "Working", value: stats.totalWorking, accent: Palette.working,
                         glyph: "⚡", pulse: stats.totalWorking > 0)
                StatTile(title: "Idle", value: stats.totalIdle, accent: Palette.idle, glyph: "☾")
            }

            tokenHero

            // 每个 agent 的聚合行：动态遍历 perTool，不再写死。
            VStack(spacing: 10) {
                ForEach(stats.perTool, id: \.tool.id) { stat in
                    ToolRow(stat: stat, grandTotal: stats.tokensAllTime.total)
                }
            }
            .padding(.top, 2)

            liveSessions

            footer
        }
        .padding(13)
        .frame(width: Dim.cardWidth, alignment: .leading)
    }

    // MARK: Header

    /// Dashboard 顶部：机器人、标题、更新提示、形态切换和菜单。
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            MascotView(mood: Mood.from(stats), size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Seeubot")
                    .font(Typo.rounded(17, .heavy))
                    .foregroundStyle(Palette.ink)
                Text("AI SESSION MONITOR")
                    .font(Typo.rounded(9, .medium))
                    .foregroundStyle(Palette.inkFaint)
                    .tracking(1.5)
            }
            Spacer(minLength: 6)
            if updateTag != nil { updateBadge }
            if hasNotch { modeToggle }
            menuButton
        }
    }

    /// 点击切换收起态形态（hanging ⇄ sides），选择会存在 `StatsStore.mode` 里。
    private var modeToggle: some View {
        HStack(spacing: 4) {
            Image(systemName: mode.icon).font(.system(size: 9, weight: .bold))
            Text(mode.label).font(Typo.rounded(10, .semibold))
        }
        .foregroundStyle(Palette.inkDim)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.06))
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)))
        .contentShape(Capsule())
        .onTapGesture { onToggleMode() }
        .help("切换形态：下挂 / 两侧")
    }

    /// The "⋯" control button — always-visible, notch-proof way to reach show/hide,
    /// switch form, check updates and **quit**.
    private var menuButton: some View {
        Image(systemName: "ellipsis.circle.fill")
            .font(.system(size: 17))
            .foregroundStyle(Palette.inkDim)
            .contentShape(Circle())
            .onTapGesture { onMenu() }
            .help("菜单 · 切换 / 隐藏 / 退出")
    }

    private var updateBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 9, weight: .bold))
            Text("Update").font(Typo.rounded(9, .bold))
        }
        .foregroundStyle(Palette.working)
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(Capsule().fill(Palette.working.opacity(0.16)))
        .contentShape(Capsule())
        .onTapGesture { onMenu() }
        .help("Update available \(updateTag ?? "")")
    }

    // MARK: Token hero

    /// 中间最大的 token 卡片：总 token、output token、今日 token 和分段条都在这里。
    private var tokenHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOTAL TOKENS")
                        .font(Typo.rounded(10, .semibold))
                        .foregroundStyle(Palette.inkDim).tracking(0.6)
                    AnimatedNumber(value: stats.tokensAllTime.total,
                                   font: Typo.rounded(34, .heavy), color: Palette.ink)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("OUTPUT").font(Typo.rounded(9, .semibold)).foregroundStyle(Palette.inkFaint)
                    AnimatedNumber(value: stats.tokensAllTime.output,
                                   font: Typo.rounded(16, .bold), color: Palette.tOutput)
                    Text("today \(Fmt.compact(stats.tokensToday.total))")
                        .font(Typo.mono(9, .semibold)).foregroundStyle(Palette.inkFaint)
                }
            }
            SegmentedTokenBar(tb: stats.tokensAllTime)
        }
        .padding(13)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                RotatingAura(working: stats.totalWorking > 0)
                    .opacity(stats.totalWorking > 0 ? 0.9 : 0.35)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.working.opacity(stats.totalWorking > 0 ? 0.22 : 0.12), lineWidth: 1.2)
        )
    }

    // MARK: Live sessions

    /// 展示最近活跃的 session chip；为空时显示“安静状态”。
    private var liveSessions: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text("LIVE SESSIONS").font(Typo.rounded(11, .bold)).foregroundStyle(Palette.inkDim)
                Text("\(stats.sessions.count)")
                    .font(Typo.rounded(10, .bold)).foregroundStyle(Palette.inkFaint)
                Spacer()
            }
            if stats.sessions.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill").foregroundStyle(Palette.idle)
                    Text("All quiet — grab a coffee ☕")
                        .font(Typo.rounded(11, .medium)).foregroundStyle(Palette.inkDim)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else {
                sessionFlow
            }
        }
    }

    /// session chip 使用自定义 FlowLayout，数量多时自动换行。
    private var sessionFlow: some View {
        // Assigning to a local turns `layout { … }` into Dim.callAsFunction
        // (a bare `FlowLayout(args) { … }` is mis-parsed as an initializer call).
        let layout = FlowLayout(spacing: 6, lineSpacing: 6)
        return layout {
            ForEach(stats.sessions.prefix(8)) { s in
                SessionChip(session: s)
            }
            if stats.sessions.count > 8 {
                Text("+\(stats.sessions.count - 8)")
                    .font(Typo.rounded(11, .bold)).foregroundStyle(Palette.inkFaint)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.05)))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text("\(stats.sessionsAllTime) sessions all-time")
                .font(Typo.rounded(9, .medium)).foregroundStyle(Palette.inkFaint)
            Spacer()
            Text(toolList)
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

struct RotatingAura: View {
    var working: Bool = false
    var body: some View {
        // working 时快速转，idle 时慢速转，避免无任务时浪费 GPU。
        TimelineView(.animation(minimumInterval: working ? 1.0 / 60 : 1.0 / 6, paused: false)) { tl in
            let a = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) / 8
            Ellipse()
                .fill(AngularGradient(
                    gradient: Gradient(colors: [Palette.claude, Palette.codex, Palette.tCacheCreate, Palette.working, Palette.claude]),
                    center: .center,
                    angle: .degrees(a * 360)))
                .frame(width: 220, height: 120)
                .blur(radius: 42)
                .offset(x: 60, y: -10)
        }
    }
}
