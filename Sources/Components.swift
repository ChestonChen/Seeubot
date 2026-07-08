import SwiftUI

// MARK: - Rolling number

/// A compact-formatted number that animates its digits when it changes.
struct AnimatedNumber: View {
    var value: Int
    var font: Font
    var color: Color = Palette.ink

    var body: some View {
        Text(Fmt.compact(value))
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(value)))
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: value)
    }
}

// MARK: - Pulsing state dot

struct PulseDot: View {
    var color: Color
    var active: Bool
    var size: CGFloat = 8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let phase = active ? (t.truncatingRemainder(dividingBy: 1.6) / 1.6) : 0
            ZStack {
                if active {
                    Circle()
                        .stroke(color, lineWidth: 1.5)
                        .scaleEffect(1 + CGFloat(phase) * 1.7)
                        .opacity((1 - phase) * 0.7)
                }
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .shadow(color: active ? color.opacity(0.8) : .clear, radius: active ? 4 : 0)
                    .scaleEffect(active ? 1 + 0.12 * CGFloat(sin(t * 4)) : 1)
            }
            .frame(width: size * 3, height: size * 3)
        }
        .frame(width: size, height: size)
    }
}

/// A compact solid dot that gently breathes (subtle glow) when active — no large
/// expanding ring, so it stays tidy in the tight collapsed pill.
struct GlowDot: View {
    var color: Color
    var active: Bool
    var size: CGFloat = 7

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !active)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let s = active ? 1 + 0.12 * CGFloat(sin(t * 4)) : 1
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .scaleEffect(s)
                .shadow(color: active ? color.opacity(0.85) : .clear, radius: active ? 3.5 : 0)
        }
        .frame(width: size, height: size)
    }
}

/// One live metric shown in the collapsed widget: a glyph/dot + animated count.
struct LiveMetric: View {
    var icon: String
    var value: Int
    var color: Color
    var pulse: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if pulse {
                GlowDot(color: color, active: true, size: 7)
            } else {
                Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            }
            AnimatedNumber(value: value, font: Typo.rounded(14, .bold), color: color)
        }
    }
}

// MARK: - Glass surfaces

struct GlassPanelBackground: View {
    var cornerRadius: CGFloat
    var accent: Color = Palette.ink
    var accentOpacity: Double = 0.18

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.13), Color.white.opacity(0.035)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accent.opacity(accentOpacity), lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 5)
    }
}

struct GlassCapsuleBackground: View {
    var accent: Color

    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
            .overlay(Capsule().stroke(accent.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Stat tile

struct StatTile: View {
    var title: String
    var value: Int
    var accent: Color
    var glyph: String
    var pulse: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if pulse {
                    PulseDot(color: accent, active: true, size: 6)
                } else {
                    Circle().fill(accent).frame(width: 6, height: 6)
                }
                Text(title)
                    .font(Typo.rounded(10, .semibold))
                    .foregroundStyle(Palette.inkDim)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                AnimatedNumber(value: value, font: Typo.rounded(26, .bold), color: Palette.ink)
                Text(glyph).font(Typo.rounded(12, .semibold)).foregroundStyle(accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(GlassPanelBackground(cornerRadius: 14, accent: accent, accentOpacity: 0.24))
    }
}

// MARK: - Segmented token bar

struct SegmentedTokenBar: View {
    var tb: TokenBreakdown
    var height: CGFloat = 12

    private var segments: [(Color, Int, String)] {
        [(Palette.tOutput, tb.output, "Output"),
         (Palette.tInput, tb.inputFresh, "Input"),
         (Palette.tCacheCreate, tb.cacheCreate, "Cache-W"),
         (Palette.tCacheRead, tb.cacheRead, "Cache-R")]
    }

    var body: some View {
        let total = max(1, tb.total)
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        Capsule()
                            .fill(seg.0)
                            .frame(width: max(seg.1 > 0 ? 3 : 0,
                                              geo.size.width * CGFloat(seg.1) / CGFloat(total)))
                    }
                }
                .frame(height: height)
                .clipShape(Capsule())
            }
            .frame(height: height)

            // legend
            HStack(spacing: 10) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    HStack(spacing: 3) {
                        Circle().fill(seg.0).frame(width: 6, height: 6)
                        Text(seg.2).font(Typo.rounded(9, .medium)).foregroundStyle(Palette.inkDim)
                        Text(Fmt.compact(seg.1)).font(Typo.mono(9, .semibold)).foregroundStyle(Palette.inkFaint)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Per-tool row

struct ToolRow: View {
    var stat: ToolStat
    var grandTotal: Int

    var body: some View {
        let accent = Palette.tool(stat.tool)
        HStack(spacing: 10) {
            // badge
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.gradient(stat.tool))
                    .frame(width: 30, height: 30)
                Text(stat.tool.glyph).font(Typo.rounded(15, .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(stat.tool.display).font(Typo.rounded(12, .bold)).foregroundStyle(Palette.ink)
                    if stat.working > 0 {
                        Label("\(stat.working)", systemImage: "bolt.fill")
                            .font(Typo.rounded(9, .bold)).foregroundStyle(Palette.working)
                            .labelStyle(.titleAndIcon)
                    }
                    if stat.idle > 0 {
                        Label("\(stat.idle)", systemImage: "moon.zzz.fill")
                            .font(Typo.rounded(9, .semibold)).foregroundStyle(Palette.idle)
                            .labelStyle(.titleAndIcon)
                    }
                    Spacer(minLength: 0)
                    Text(Fmt.compact(stat.tokensAllTime.total))
                        .font(Typo.mono(11, .semibold)).foregroundStyle(accent)
                }
                // share bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.06))
                        Capsule().fill(Palette.gradient(stat.tool))
                            .frame(width: geo.size.width *
                                   CGFloat(stat.tokensAllTime.total) / CGFloat(max(1, grandTotal)))
                    }
                }
                .frame(height: 5)
            }
        }
    }
}

// MARK: - Live session chip

struct SessionChip: View {
    var session: LiveSession

    var body: some View {
        let working = session.state == .working
        HStack(spacing: 6) {
            PulseDot(color: working ? Palette.working : Palette.idle, active: working, size: 6)
            Text(session.tool.glyph)
                .font(Typo.rounded(9, .bold))
                .foregroundStyle(Palette.tool(session.tool))
            Text(session.project)
                .font(Typo.rounded(11, .semibold))
                .foregroundStyle(working ? Palette.ink : Palette.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 140, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(GlassCapsuleBackground(accent: working ? Palette.working : Palette.idle))
    }
}
