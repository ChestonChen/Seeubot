//只负责：选屏幕 → 建面板 → 把视图塞进去 → 摆到顶边 → 显示出来。
import AppKit
import SwiftUI
@MainActor//这个类只能在主线程使用
final class AppDelegate: NSObject, NSApplicationDelegate {//在内部实现指定的生命周期方法
    static let homepage = "https://github.com/ChestonChen/Seeubot" //菜单栏点击对应homepage按钮时跳转对应地址
    private var panel: NotchPanel! //创建一个panel对象
    private var store: StatsStore! //创建状态对象
    private var hoverTimer: Timer? //来一个定时器 每0.1s触发一次闭包
    private var statusItem: NSStatusItem?
    private var widgetVisible = true
    private weak var headerItem: NSMenuItem?
    private weak var hangingItem: NSMenuItem?
    private weak var sidesItem: NSMenuItem?
    private weak var visItem: NSMenuItem?
    func applicationDidFinishLaunching(_ note: Notification) {//app的启动函数
        NSApp.setActivationPolicy(.accessory)//设置一个没有 Dock 图标、不出现在 `Cmd+Tab`、启动也不抢焦点的app
        let screen = Self.targetScreen()//在所有屏幕里挑第一块「顶部有刘海」的；挑不到就用主屏
        //无刘海safeAreaInsets.top ==0
        let metrics = NotchMetrics.measure(screen)
        store = StatsStore(metrics: metrics) //初始化类
        store.onMenu = { [weak self] in self?.showControlMenu() }//
        let root = NotchRootView(store: store)//取变量
        let hosting = FirstMouseHostingView(rootView: root)//赋值第一次点击的能力
        hosting.frame = NSRect(x: 0, y: 0, width: Dim.panelWidth, height: Dim.panelHeight)//视图定尺寸
        hosting.autoresizingMask = [.width, .height]//父视图变化，子视图跟着变
        panel = NotchPanel(size: NSSize(width: Dim.panelWidth, height: Dim.panelHeight))//创建真正的panel
        panel.contentView = hosting//把包装好的视图设成窗口的**内容视图**——从此 SwiftUI 画的东西就显示在这块面板上
        position(on: screen)//把面板挪到屏幕顶部中央，屏幕顶 − 面板高
        panel.orderFrontRegardless()//强制把窗口显示到最前，即使这个 App 没被激活也照样显示——配件 App 从来不会「被激活」
        NotificationCenter.default.addObserver(//屏幕参数变化（插拔显示器、唤醒）时调用指定方法，重新量尺寸、重新摆位置
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        startHoverTracking()
        setupMenuBar()//

    }
    private func setupMenuBar() {//设置菜单
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
                             accessibilityDescription: "Seeubot")
                     ?? NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "Seeubot") {
            img.isTemplate = true
            item.button?.image = img
        } else {
            item.button?.title = "◆"
        }
        let menu = NSMenu()
        menu.delegate = self
        let header = NSMenuItem(title: "Seeubot", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header); headerItem = header
        menu.addItem(.separator())
        let hang = NSMenuItem(title: "Hanging pill", action: #selector(setHanging), keyEquivalent: "")
        hang.target = self; menu.addItem(hang); hangingItem = hang
        let sides = NSMenuItem(title: "Bar", action: #selector(setSides), keyEquivalent: "")
        sides.target = self; menu.addItem(sides); sidesItem = sides
        menu.addItem(.separator())
        let vis = NSMenuItem(title: "Hide widget", action: #selector(toggleVisibility), keyEquivalent: "h")
        vis.target = self; menu.addItem(vis); visItem = vis
        menu.addItem(.separator())
        let gh = NSMenuItem(title: "Homepage…", action: #selector(openHomepage), keyEquivalent: "")
        gh.target = self; menu.addItem(gh)
        let quit = NSMenuItem(title: "Quit Seeubot", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }
    @objc private func setHanging() { store.mode = .hanging; ensureVisible() }
    @objc private func setSides() { store.mode = .sides; ensureVisible() }
    @objc private func openHomepage() {
        if let u = URL(string: Self.homepage) { NSWorkspace.shared.open(u) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggleVisibility() {
        widgetVisible.toggle()
        if widgetVisible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }
    private func ensureVisible() {
        if !widgetVisible { widgetVisible = true; panel.orderFrontRegardless() }
    }
    private func showControlMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
    private func position(on screen: NSScreen?) {
        guard let screen else { return }
        let f = screen.frame//整块物理屏
        let x = f.midX - Dim.panelWidth / 2 //规定x
        let y = f.maxY - Dim.panelHeight    //规定y
        panel.setFrame(NSRect(x: x, y: y, width: Dim.panelWidth, height: Dim.panelHeight),
                       display: true)//设置完立即重绘
    }
    @objc private func screensChanged() {
        let screen = Self.targetScreen()//
        store.updateMetrics(NotchMetrics.measure(screen))//更新几何的函数
        position(on: Self.targetScreen())
    }
    private func startHoverTracking() {//开启鼠标位置监控
        let t = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in //创建一个定时器
            MainActor.assumeIsolated { self?.updateHover() }//加到主线程同步执行
        }
        RunLoop.main.add(t, forMode: .common)//比如加入到runloop才能启动
        hoverTimer = t
    }
    private func updateHover() {//每0.1s轮询的任务，检测鼠标是否在热区
        let mouse = NSEvent.mouseLocation//捕获鼠标坐标
        let pf = panel.frame
        let m = store.metrics
        let collapsed: NSRect //收起热区
        if !m.hasNotch {//没有刘海
            let w = m.notchWidth + Dim.barSideWidth * 2
            let h = m.menuBarHeight
            collapsed = NSRect(x: pf.midX - w / 2, y: pf.maxY - h - 6, width: w, height: h + 6)
        } else {//有刘海
            let pillTopY = pf.maxY - m.menuBarHeight
            collapsed = NSRect(x: pf.midX - m.notchWidth / 2 - 8,
                               y: pillTopY - Dim.pillHeight - 6,
                               width: m.notchWidth + 16,
                               height: Dim.pillHeight + 6)
        }
        let expanded = pf.insetBy(dx: -6, dy: -6)//展开的热区
        let active = store.hover ? expanded : collapsed //防抖，大热区包括小热区
        let inside = active.contains(mouse)
        panel.ignoresMouseEvents = !inside //如果在热区内就接受鼠标事件
        if inside != store.hover { //鼠标坐标发生变化了再改状态
            store.hover = inside
        }
    }
}
extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let s = store.stats
        headerItem?.title = "Seeubot · \(s.totalWorking) working · \(s.totalIdle) idle"
        let notch = store.metrics.hasNotch
        hangingItem?.isHidden = !notch
        sidesItem?.isHidden = !notch
        hangingItem?.state = store.mode == .hanging ? .on : .off
        sidesItem?.state = store.mode == .sides ? .on : .off
        visItem?.title = widgetVisible ? "Hide widget" : "Show widget"
    }
}