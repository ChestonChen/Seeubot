import SwiftUI

/// A rounded rectangle with square TOP corners and rounded BOTTOM corners, so the
/// top edge merges flush with the notch / menu-bar line and the body bulges below.
struct IslandShape: Shape {
    var bottomRadius: CGFloat
    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 400
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Root widget. Two collapsed forms (user-switchable):
///   • hanging — one pill below the notch center
///   • sides   — two ears flanking the notch
/// Both expand into the same dashboard hanging below the notch.
struct NotchRootView: View {
    @ObservedObject var store: StatsStore

    private var m: NotchMetrics { store.metrics }
    private var expanded: Bool { store.hover }
    private var mood: Mood { Mood.from(store.stats) }

    var body: some View {
        morphingIsland
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: store.hover)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: store.mode)
            .frame(width: Dim.panelWidth, height: Dim.panelHeight, alignment: .top)
    }

    // Non-notched Macs have no "hanging" form — always use the flat bar.
    private var isSides: Bool { !m.hasNotch || store.mode == .sides }
    private var collapsedWidth: CGFloat { isSides ? SidesBar.width(m) : m.notchWidth }
    private var width: CGFloat { expanded ? Dim.cardWidth : collapsedWidth }
    private var corner: CGFloat { expanded ? Dim.cardCorner : (isSides ? Dim.barCorner : Dim.pillCorner) }
    // Bar/flat-collapsed content sits at the menu-bar line (no top pad); everything else
    // clears the menu bar / notch. Animating this pad grows the bar smoothly into the card.
    private var topPad: CGFloat { (expanded || !isSides) ? m.menuBarHeight : 0 }

    /// ONE continuous view used by BOTH modes. Its width, corner, top-pad and content
    /// all animate together under the parent `.animation`, so the sides form expands
    /// and collapses just as smoothly as the hanging form.
    private var morphingIsland: some View {
        VStack(spacing: 0) {
            if expanded {
                DashboardBody(stats: store.stats, loaded: store.loaded,
                              mode: store.mode, hasNotch: m.hasNotch,
                              updateTag: store.updateAvailable,
                              onToggleMode: { store.toggleMode() },
                              onMenu: { store.onMenu?() })
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                    })
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if isSides {
                SidesBar(stats: store.stats, metrics: m)
                    .transition(.opacity)
            } else {
                CollapsedPill(stats: store.stats, metrics: m)
                    .transition(.opacity)
            }
        }
        .frame(width: width)
        .padding(.top, topPad)
        .background(
            IslandShape(bottomRadius: corner)
                .fill(LinearGradient(colors: [Palette.notchBlack, Palette.panelBottom],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(IslandShape(bottomRadius: corner).stroke(Color.white.opacity(0.09), lineWidth: 1))
        .clipShape(IslandShape(bottomRadius: corner))
        .overlay(alignment: .bottom) { moodUnderglow(width: width) }
        .shadow(color: .black.opacity(0.32), radius: expanded ? 12 : 7, x: 0, y: expanded ? 6 : 3)
        .onPreferenceChange(HeightKey.self) { store.dashboardHeight = $0 }
    }

    private func moodUnderglow(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(mood.bulb)
            .frame(width: width * 0.5, height: 3)
            .blur(radius: 5)
            .opacity(mood == .sleeping ? 0.22 : 0.6)
            .offset(y: 3)
            .animation(.easeInOut(duration: 0.6), value: mood.bulb)
    }
}
