import SwiftUI
import AppKit
//规定尺寸和圆角，用于后续的布局
enum Dim {
    static let panelWidth: CGFloat  = 440//面板宽度
    static let panelHeight: CGFloat = 540//面板高度
    static let pillHeight: CGFloat  = 34//胶囊高度
    static let pillCorner: CGFloat  = 16//胶囊圆角
    static let cardWidth: CGFloat   = 384//看板宽度 一个panel有多个看板
    static let cardCorner: CGFloat  = 24//看板圆角
    static let barSideWidth: CGFloat = 84//有刘海长条宽度
    static let barCorner: CGFloat = 10//有刘海长条圆角
    static let flatBarWidth: CGFloat = 208//无刘海长条宽度
}

enum Palette {//所有组件的颜色
    static let notchBlack   = Color(red: 0.04, green: 0.04, blue: 0.05)//岛的顶部颜色到底颜色渐变
    static let panelBottom  = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let ink          = Color.white //ink是文字色
    static let inkDim       = Color.white.opacity(0.62)
    static let inkFaint     = Color.white.opacity(0.34)
    static let working      = Color(red: 0.24, green: 0.86, blue: 0.52)//状态色
    static let idle         = Color(red: 0.56, green: 0.65, blue: 1.00)
    static let sleepy       = Color(red: 0.45, green: 0.47, blue: 0.58)
    static let claude       = Color(red: 0.98, green: 0.55, blue: 0.38)//按工具和按 token 类型的两组颜色。成对出现（主色 + 深色）是为了做渐变徽章
    static let claudeDeep   = Color(red: 0.92, green: 0.33, blue: 0.20)
    static let codex        = Color(red: 0.37, green: 0.90, blue: 0.80)
    static let codexDeep    = Color(red: 0.09, green: 0.72, blue: 0.64)
    static let tOutput      = Color(red: 0.35, green: 0.87, blue: 0.53)
    static let tInput       = Color(red: 0.45, green: 0.68, blue: 1.00)
    static let tCacheCreate = Color(red: 0.72, green: 0.55, blue: 1.00)
    static let tCacheRead   = Color(red: 0.36, green: 0.45, blue: 0.55)

    //给定一个agent返回他的name，颜色，图案
    static func tool(_ t: AgentDescriptor) -> Color {
        switch t.id {
        case AgentDescriptor.claude.id: return claude
        case AgentDescriptor.codex.id: return codex
        default: return inkDim
        }
    }
    //深色模式
    static func toolDeep(_ t: AgentDescriptor) -> Color {
        switch t.id {
        case AgentDescriptor.claude.id: return claudeDeep
        case AgentDescriptor.codex.id: return codexDeep
        default: return inkFaint
        }
    }
    //颜色转换
    static func gradient(_ t: AgentDescriptor) -> LinearGradient {
        LinearGradient(colors: [tool(t), toolDeep(t)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum Typo {//返回圆角字体」和「等宽字体」
//font是swiftui字体类型
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

struct NotchMetrics { //计算刘海宽，菜单栏多高等尺寸，整个布局尺寸源头
    var hasNotch: Bool //是否有刘海
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var menuBarHeight: CGFloat
    var screenWidth: CGFloat
    static func measure(_ screen: NSScreen?) -> NotchMetrics {
        //静态工厂方法：不用先造对象，直接 `NotchMetrics.measure(屏幕)` 就能算出一整套尺寸
        guard let screen else {
            return NotchMetrics(hasNotch: false, notchWidth: 0, notchHeight: 0,
                                menuBarHeight: 24, screenWidth: 1440)
        }
        let full = screen.frame.width
        let hasNotch = screen.safeAreaInsets.top > 1
            && screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
            //刘海**左侧**和**右侧**的可绘制区域。没有刘海的机器上它们是 nil
        var notchWidth: CGFloat = 0
        if hasNotch, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchWidth = max(120, full - l.width - r.width)//给个保底不然药丸状态看不见
        }
        let notchHeight = hasNotch ? screen.safeAreaInsets.top : 0
        let menuBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)//计算可用屏幕的高（菜单栏和 Dock）
        return NotchMetrics(hasNotch: hasNotch, notchWidth: notchWidth, notchHeight: notchHeight,
                            menuBarHeight: menuBar, screenWidth: full)
    }
}


