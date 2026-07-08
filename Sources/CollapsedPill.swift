import SwiftUI

/// Collapsed content for the **hanging** mode: mascot + working/idle counts in a
/// single row that fits within the notch width and covers no menu-bar tools.
struct CollapsedPill: View {
    var stats: DashStats
    var metrics: NotchMetrics

    private var mood: Mood { Mood.from(stats) }

    var body: some View {
        HStack(spacing: 12) {
            WorkingMascotRunway(mood: mood, active: stats.totalWorking > 0,
                                trackWidth: 96, height: Dim.pillHeight,
                                mascotSize: 23, restingEdge: .left)
                .frame(width: 96, height: Dim.pillHeight)
                .clipped()
            LiveMetric(icon: "bolt.fill", value: stats.totalWorking,
                       color: Palette.working, pulse: stats.totalWorking > 0)
            LiveMetric(icon: "moon.zzz.fill", value: stats.totalIdle, color: Palette.idle)
        }
        .frame(height: Dim.pillHeight)
    }
}
