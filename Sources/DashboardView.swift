import SwiftUI

/// The expanded dashboard body shown below the notch when hovering.
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

            // Session summary tiles
            HStack(spacing: 8) {
                StatTile(title: "Sessions", value: stats.totalLive, accent: Palette.ink.opacity(0.9), glyph: "◎")
                StatTile(title: "Working", value: stats.totalWorking, accent: Palette.working,
                         glyph: "⚡", pulse: stats.totalWorking > 0)
                StatTile(title: "Idle", value: stats.totalIdle, accent: Palette.idle, glyph: "☾")
            }

            tokenHero

            // Per-tool split
            VStack(spacing: 10) {
                ToolRow(stat: stats.stat(for: .claude), grandTotal: stats.tokensAllTime.total)
                ToolRow(stat: stats.stat(for: .codex), grandTotal: stats.tokensAllTime.total)
            }
            .padding(.top, 2)

            liveSessions

            footer
        }
        .padding(13)
        .frame(width: Dim.cardWidth, alignment: .leading)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            MascotView(mood: Mood.from(stats), size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Seeybot")
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

    /// Tap to switch the collapsed form (hanging ⇄ sides). Choice is remembered.
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
                    .fill(Color.white.opacity(0.045))
                RotatingAura(working: stats.totalWorking > 0)
                    .opacity(stats.totalWorking > 0 ? 0.9 : 0.35)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 1)
        )
    }

    // MARK: Live sessions

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
            Text("Claude Code · Codex")
                .font(Typo.rounded(9, .medium)).foregroundStyle(Palette.inkFaint)
        }
    }
}

// MARK: - Rotating conic aura behind the token total

struct RotatingAura: View {
    var working: Bool = false
    var body: some View {
        // Idle: crawl slowly (saves GPU); working: smooth rotation.
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
