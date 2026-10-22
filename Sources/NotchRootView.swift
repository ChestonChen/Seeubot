import SwiftUI

// 系统 API 速览：
// - Shape / Path：SwiftUI 自定义图形协议和路径，用来画特殊圆角 island 外形。
// - @ObservedObject：订阅 `StatsStore`，store 变化会触发 body 重新计算。
// - VStack：纵向排布 UI。
// - .transition / .animation：控制胶囊、bar、dashboard 切换时的过渡动画。
// - .background / .overlay / .clipShape / .shadow：SwiftUI 常用外观修饰符。
/// 胶囊/卡片共用的外形：顶部是直角贴住屏幕顶边，底部圆角向下展开。
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

/// 顶部组件的 SwiftUI 根视图。
///
/// 这里负责把两种可见状态串起来：
/// - 收起：刘海下方单胶囊，或横跨刘海的长条
/// - 展开：鼠标 hover 后的 dashboard
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

    // 无刘海 Mac 没有 hanging 形态，统一走 flat/sides bar。
    private var isSides: Bool { !m.hasNotch || store.mode == .sides }
    private var collapsedWidth: CGFloat { isSides ? SidesBar.width(m) : m.notchWidth }
    private var width: CGFloat { expanded ? Dim.cardWidth : collapsedWidth }
    private var corner: CGFloat { expanded ? Dim.cardCorner : (isSides ? Dim.barCorner : Dim.pillCorner) }
    // Bar/flat-collapsed content sits at the menu-bar line (no top pad); everything else
    // clears the menu bar / notch. Animating this pad grows the bar smoothly into the card.
    private var topPad: CGFloat { (expanded || !isSides) ? m.menuBarHeight : 0 }

    /// 胶囊和 dashboard 的 morph 主体。
    /// 宽度、圆角、顶部 padding、内部内容都在同一个 view 内动画，
    /// 所以用户看到的是“一个组件变形”，不是两个组件硬切。
    private var morphingIsland: some View {
        VStack(spacing: 0) {
            if expanded {
                DashboardBody(stats: store.stats, loaded: store.loaded,
                              mode: store.mode, hasNotch: m.hasNotch,
                              updateTag: store.updateAvailable,
                              onToggleMode: { store.toggleMode() },
                              onMenu: { store.onMenu?() })
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
    }

    /// 底部状态光：working/idle/sleeping 会用不同颜色给组件一个很弱的状态提示。
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
