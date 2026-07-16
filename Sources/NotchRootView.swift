import SwiftUI

// 系统 API 速览：
// - Shape / Path：SwiftUI 自定义图形协议和路径，用来画特殊圆角 island 外形。
// - PreferenceKey：子视图向父视图回传布局信息，这里用来测 dashboard 高度。
// - @ObservedObject：订阅 `StatsStore`，store 变化会触发 body 重新计算。
// - VStack：纵向排布 UI。
// - GeometryReader：读取子视图实际尺寸。
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
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        let r = min(bottomRadius, rect.height / 2, rect.width / 2)
        // 系统 API（行级）：Path 是 SwiftUI 矢量路径，用来画线条/形状。
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

/// 顶部组件的 SwiftUI 根视图。
///
/// 这里负责把三种可见状态串起来：
/// - hanging：刘海下方单胶囊
/// - sides：刘海两侧 / 无刘海顶部 bar
/// - expanded：鼠标 hover 后展开的 dashboard
// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct NotchRootView: View {
    // 系统 API（行级）：@ObservedObject 让 SwiftUI View 订阅外部 ObservableObject。
    @ObservedObject var store: StatsStore

    private var m: NotchMetrics { store.metrics }
    private var expanded: Bool { store.hover }
    private var mood: Mood { Mood.from(store.stats) }

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        morphingIsland
            // 系统 API（行级）：.animation 绑定状态变化时的动画。
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: store.hover)
            // 系统 API（行级）：.animation 绑定状态变化时的动画。
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: store.mode)
            // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
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
    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private var morphingIsland: some View {
        // 系统 API（行级）：VStack 纵向排列子视图。
        VStack(spacing: 0) {
            if expanded {
                DashboardBody(stats: store.stats, loaded: store.loaded,
                              mode: store.mode, hasNotch: m.hasNotch,
                              updateTag: store.updateAvailable,
                              onToggleMode: { store.toggleMode() },
                              onMenu: { store.onMenu?() })
                    // 系统 API（行级）：GeometryReader 读取父容器给出的尺寸。
                    .background(GeometryReader { proxy in
                        // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
                        Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                    })
                    // 系统 API（行级）：.transition 设置视图插入/移除时的过渡效果。
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if isSides {
                SidesBar(stats: store.stats, metrics: m)
                    // 系统 API（行级）：.transition 设置视图插入/移除时的过渡效果。
                    .transition(.opacity)
            } else {
                CollapsedPill(stats: store.stats, metrics: m)
                    // 系统 API（行级）：.transition 设置视图插入/移除时的过渡效果。
                    .transition(.opacity)
            }
        }
        // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
        .frame(width: width)
        // 系统 API（行级）：.padding 设置内边距。
        .padding(.top, topPad)
        // 系统 API（行级）：.background 给视图添加背景层。
        .background(
            IslandShape(bottomRadius: corner)
                // 系统 API（行级）：LinearGradient 创建线性渐变。
                .fill(LinearGradient(colors: [Palette.notchBlack, Palette.panelBottom],
                                     startPoint: .top, endPoint: .bottom))
        )
        // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
        .overlay(IslandShape(bottomRadius: corner).stroke(Color.white.opacity(0.09), lineWidth: 1))
        // 系统 API（行级）：.clipShape 按指定形状裁剪视图。
        .clipShape(IslandShape(bottomRadius: corner))
        // 系统 API（行级）：.overlay 在视图上方叠加一层内容。
        .overlay(alignment: .bottom) { moodUnderglow(width: width) }
        // 系统 API（行级）：.shadow 给视图添加阴影。
        .shadow(color: .black.opacity(0.32), radius: expanded ? 12 : 7, x: 0, y: expanded ? 6 : 3)
        // 系统 API（行级）：.onPreferenceChange 监听子视图传回的 PreferenceKey。
        .onPreferenceChange(HeightKey.self) { store.dashboardHeight = $0 }
    }

    /// 底部状态光：working/idle/sleeping 会用不同颜色给组件一个很弱的状态提示。
    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private func moodUnderglow(width: CGFloat) -> some View {
        // 系统 API（行级）：RoundedRectangle 是 SwiftUI 圆角矩形形状。
        RoundedRectangle(cornerRadius: 3)
            // 系统 API（行级）：.fill 用颜色或渐变填充形状。
            .fill(mood.bulb)
            // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
            .frame(width: width * 0.5, height: 3)
            // 系统 API（行级）：.blur 给视图添加模糊效果。
            .blur(radius: 5)
            // 系统 API（行级）：.opacity 设置透明度。
            .opacity(mood == .sleeping ? 0.22 : 0.6)
            // 系统 API（行级）：.offset 在布局后偏移视图位置。
            .offset(y: 3)
            // 系统 API（行级）：.animation 绑定状态变化时的动画。
            .animation(.easeInOut(duration: 0.6), value: mood.bulb)
    }
}
