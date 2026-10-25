//整个看板的view
import SwiftUI
//定义看板需要什么数据以及布局

struct DashboardBody: View {
    var stats: DashStats
    var loaded: Bool
    var mode: WidgetMode = .hanging  
    var hasNotch: Bool = true
    var onToggleMode: () -> Void = {}
    var onMenu: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { //纵向排列 间距10 左对齐
            header
            HStack(spacing: 8) {
                StatTile(title: "Sessions", value: stats.totalLive, accent: Palette.ink.opacity(0.9), glyph: "◎")
                StatTile(title: "Working", value: stats.totalWorking, accent: Palette.working,
                         glyph: "⚡", pulse: stats.totalWorking > 0)
                StatTile(title: "Idle", value: stats.totalIdle, accent: Palette.idle, glyph: "☾")
            }
            tokenHero
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
            if hasNotch { modeToggle }
            menuButton
        }
    }
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
    private var menuButton: some View {
        Image(systemName: "ellipsis.circle.fill")
            .font(.system(size: 17))
            .foregroundStyle(Palette.inkDim)
            .contentShape(Circle())
            .onTapGesture { onMenu() }
            .help("菜单 · 切换 / 隐藏 / 退出")
    }
    //总token使用量面板部分
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
    //活会话统计部分
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
    private var sessionFlow: some View {//session胶囊排列
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
    }//agent列表
    private var toolList: String {
        let names = stats.perTool.map { $0.tool.display }
        return names.isEmpty ? "No agents" : names.joined(separator: " · ")
    }
}
// ┌─ ① header ────────────────────────────────┐
// │ 🤖  Seeubot                        [Bar] ⋯ │
// ├─ ② 三个统计块 ────────────────────────────┤
// │ [Sessions 3] [Working 2] [Idle 1]         │
// ├─ ③ tokenHero ★★★★★ ──────────────────────┤
// │ TOTAL TOKENS                    OUTPUT     │
// │ 3.4B                              1.2B     │
// │                                 today 12K  │
// │ ▓▓▓▓▓▓▓▓▓▓▓▒▒▒▒▒▒░░░░░                    │
// ├─ ④ 每个 agent 一行 ───────────────────────┤
// │ [✦] Claude      12.3M  ▓▓▓▓▓░             │
// │ [◆] Codex        4.1M  ▓▓░░░░░            │
// ├─ ⑤ LIVE SESSIONS ─────────────────────────┤
// │ ● ✦ Seeubot  ● ◆ api  (+2)                │
// ├─ ⑥ footer ────────────────────────────────┤
// │ 42 sessions all-time · Claude·Codex        │
// └───────────────────────────────────────────┘

//token卡背后的彩色雾效果视图
struct RotatingAura: View {
    var working: Bool = false
    var body: some View {
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
