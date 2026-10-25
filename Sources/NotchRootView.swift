import SwiftUI
// struct NotchRootView: View { //遵循view 实现body即可显现
//     var body: some View {//靠编译器推导视图类型，渲染调用body获得值
//         VStack(spacing: 0) { //vstack 垂直堆叠视图，spacing: 0 间距为0
//             RoundedRectangle(cornerRadius: Dim.pillCorner)//圆角
//                 .fill(Color.black)//填充黑色
//                 .frame(width: 244, height: Dim.pillHeight)//设置宽度为244，高度为胶囊高度
//         }
//         .frame(width: Dim.panelWidth, height: Dim.panelHeight, alignment: .top)//设置宽度为面板宽度，高度为面板高度，对齐方式为顶部 把上面的设置尺寸都包起来
//         //swiftui .frame是越在下面设置尺寸，越在外层显示，包住上面的尺寸
//     }//效果是电脑上方有个黑块
// }

struct IslandShape: Shape {//SwiftUI 的形状协议 需要实现path方法
    var bottomRadius: CGFloat //底部圆角半径
    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.height / 2, rect.width / 2) //防止圆角畸形
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

//把闭环0的黑矩形塞进岛的轮廓里
struct NotchRootView: View {
    @ObservedObject var store: StatsStore //观察者看到publish的属性改变后会标记要重新计算body
    private var m: NotchMetrics { store.metrics }
    private var expanded: Bool { store.hover }
    private var mood: Mood { Mood.from(store.stats) }
    var body: some View {
        morphingIsland
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: store.hover)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: store.mode)
            .frame(width: Dim.panelWidth, height: Dim.panelHeight, alignment: .top)
    }
    private var isSides: Bool { !m.hasNotch || store.mode == .sides }//是否是长条态
    private var collapsedWidth: CGFloat { isSides ? SidesBar.width(m) : m.notchWidth }
    private var width: CGFloat { expanded ? Dim.cardWidth : collapsedWidth }
    private var corner: CGFloat { expanded ? Dim.cardCorner : (isSides ? Dim.barCorner : Dim.pillCorner) }
    private var topPad: CGFloat { (expanded || !isSides) ? m.menuBarHeight : 0 }
    private var morphingIsland: some View {
        VStack(spacing: 0) {
            if expanded {//展开渲染面板
                DashboardBody(stats: store.stats, loaded: store.loaded,
                              mode: store.mode, hasNotch: m.hasNotch,
                              onToggleMode: { store.toggleMode() },
                              onMenu: { store.onMenu?() })
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if isSides { //长条
                SidesBar(stats: store.stats, metrics: m)
                    .transition(.opacity)
            } else {//普通药丸态
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