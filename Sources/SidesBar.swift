import SwiftUI

/// Collapsed CONTENT for the **sides / flat** form. The black bar background + clipping
/// is supplied by the shared morphing island in `NotchRootView`.
///
/// - Notched Macs: one bar spanning the notch — mascot on the left, a fixed-width empty
///   gap over the notch, live metrics on the right.
/// - Non-notched Macs: one flat continuous bar (no center gap) — mascot + metrics in a row.
struct SidesBar: View {
    var stats: DashStats
    var metrics: NotchMetrics

    private var mood: Mood { Mood.from(stats) }
    private var barHeight: CGFloat { metrics.menuBarHeight }

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
        WorkingMascotRunway(mood: mood, active: stats.totalWorking > 0,
                            trackWidth: Dim.barSideWidth, height: barHeight,
                            mascotSize: min(barHeight * 0.62, 21), restingEdge: .right)
    }

    var body: some View {
        Group {
            if metrics.notchWidth > 0 {
                // Notched: content flanks the empty notch gap.
                HStack(spacing: 0) {
                    mascot
                        .frame(width: Dim.barSideWidth)
                    Color.clear.frame(width: metrics.notchWidth)
                    HStack(spacing: 0) {
                        HStack(spacing: 10) { working; idle }
                        Spacer(minLength: 0)
                    }
                    .frame(width: Dim.barSideWidth)
                }
            } else {
                // Non-notched: one continuous row, no gap.
                HStack(spacing: 13) {
                    WorkingMascotRunway(mood: mood, active: stats.totalWorking > 0,
                                        trackWidth: 56, height: barHeight,
                                        mascotSize: min(barHeight * 0.62, 21), restingEdge: .right)
                    working
                    idle
                }
            }
        }
        .frame(width: SidesBar.width(metrics), height: barHeight)
    }
}
