import AppKit
import SwiftUI

// 系统 API 速览：
// - NSApplicationDelegate：AppKit 的应用生命周期回调协议，app 启动完成后会调用 applicationDidFinishLaunching。
// - NSStatusItem / NSMenu / NSMenuItem：macOS 菜单栏图标和下拉菜单。
// - NotificationCenter.addObserver：监听系统事件，这里用于屏幕参数变化。
// - Timer + RunLoop：定时执行任务，这里用于 hover 轮询和定期检查更新。
// - NSEvent.mouseLocation：读取全局鼠标位置，用来判断鼠标是否进入组件热区。
// - NSWorkspace.shared.open：调用系统打开网页链接。
// - Task { @MainActor in ... }：从异步回调切回主线程更新 UI 状态。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let homepage = "https://github.com/ChestonChen/Seeubot"

    // AppDelegate 是 macOS 端入口：负责创建悬浮窗、菜单栏、hover 轮询和更新检查。
    private var panel: NotchPanel!
    private var store: StatsStore!
    private var hoverTimer: Timer?

    private var statusItem: NSStatusItem?
    private var widgetVisible = true
    private weak var headerItem: NSMenuItem?
    private weak var hangingItem: NSMenuItem?
    private weak var sidesItem: NSMenuItem?
    private weak var visItem: NSMenuItem?

    /// App 启动后的主入口：创建数据仓库、SwiftUI 根视图、透明 NSPanel，并开始 hover 轮询。
    func applicationDidFinishLaunching(_ note: Notification) {
        // 设为配件 App：不进 Dock，不抢前台激活（适合菜单栏/刘海挂件）。
        // 系统 API（行级）：NSApp 是当前 AppKit 应用的快捷全局对象。
        NSApp.setActivationPolicy(.accessory)

        // 选一块要贴的屏幕：优先带刘海的，否则主屏。
        let screen = Self.targetScreen()
        // 量这块屏的刘海宽、菜单栏高等几何信息。
        let metrics = NotchMetrics.measure(screen)
        // 建状态仓库：立刻采一次会话数据，并启动 1s 定时刷新。
        store = StatsStore(metrics: metrics)
        // 岛内「⋯」按钮点下去时，弹出和状态栏同一套控制菜单。
        store.onMenu = { [weak self] in self?.showControlMenu() }

        // SwiftUI 根视图：折叠胶囊 ⇄ 展开 dashboard，数据来自 store。
        let root = NotchRootView(store: store)
        // 用可接收「第一次点击」的 NSHostingView 包住 SwiftUI（窗口本身不激活也能点）。
        let hosting = FirstMouseHostingView(rootView: root)
        // 把 hosting 视图尺寸设成面板大小（440×540）。
        hosting.frame = NSRect(x: 0, y: 0, width: Dim.panelWidth, height: Dim.panelHeight)
        // 面板改尺寸时，hosting 跟着宽高一起变。
        hosting.autoresizingMask = [.width, .height]

        // 创建透明、无边框、默认点击穿透的悬浮 NSPanel。
        panel = NotchPanel(size: NSSize(width: Dim.panelWidth, height: Dim.panelHeight))
        // 把 SwiftUI hosting 设成面板的内容视图。
        panel.contentView = hosting
        // 把面板移到目标屏顶部中央（顶边贴齐屏幕顶，盖住刘海区域）。
        position(on: screen)
        // 立刻显示面板（不依赖 App 是否前台）。
        panel.orderFrontRegardless()

        // 监听屏幕参数变化（外接屏/分辨率/睡眠唤醒）：回调里重测 notch 并重新定位。
        // 系统 API（行级）：NotificationCenter.addObserver 注册系统通知监听。
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            // 系统 API（行级）：didChangeScreenParametersNotification 是屏幕参数变化通知。
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // 每 0.1s 轮询鼠标位置，更新 store.hover，驱动展开/收起。
        startHoverTracking()
        // 创建右上角状态栏图标和菜单（形态切换 / 显隐 / 退出等）。
        setupMenuBar()
        // 查一次 GitHub 是否有新版本，并每 6 小时再查。
        scheduleUpdateChecks()
    }

    // MARK: - Update checks

    private var updateItem: NSMenuItem?

    /// 启动时查一次 GitHub Release，之后每 6 小时查一次是否有新版本。
    private func scheduleUpdateChecks() {
        checkForUpdate()
        // re-check every 6 hours
        // 系统 API（行级）：Timer 是系统定时器，用于周期性执行闭包。
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            // 系统 API（行级）：MainActor.assumeIsolated 告诉编译器当前代码在主线程上下文。
            MainActor.assumeIsolated { self?.checkForUpdate() }
        }
        // 系统 API（行级）：RunLoop.main.add 把 Timer 加入主运行循环。
        RunLoop.main.add(t, forMode: .common)
    }

    /// 只更新 `store.updateAvailable`，不影响主监控功能。
    private func checkForUpdate() {
        Updater.checkLatest { tag in
            // 系统 API（行级）：Task { @MainActor } 把异步回调切回主线程更新 UI。
            Task { @MainActor in self.store.updateAvailable = tag }
        }
    }

    // 系统 API（行级）：NSWorkspace.shared.open 调用系统默认方式打开 URL 或文件。
    @objc private func openReleases() { NSWorkspace.shared.open(Updater.releasesURL) }

    // MARK: - Menu bar (control surface: show/hide, switch form, quit)

    /// 创建右上角状态栏菜单，提供切换形态、隐藏组件、打开主页和退出入口。
    private func setupMenuBar() {
        // 系统 API（行级）：NSStatusBar 创建菜单栏状态项，也就是右上角小图标入口。
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 系统 API（行级）：NSImage(systemSymbolName:) 从系统 SF Symbols 里取菜单栏图标。
        if let img = NSImage(systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
                             accessibilityDescription: "Seeubot")
                     // 系统 API（行级）：NSImage(systemSymbolName:) 从系统 SF Symbols 里取菜单栏图标。
                     ?? NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "Seeubot") {
            img.isTemplate = true
            item.button?.image = img
        } else {
            item.button?.title = "◆"
        }

        // 系统 API（行级）：NSMenu 是 AppKit 下拉菜单容器。
        let menu = NSMenu()
        // 系统 API（行级）：AppKit 用 delegate 接收应用生命周期回调。
        menu.delegate = self

        // 系统 API（行级）：NSMenuItem 是 AppKit 菜单中的一项。
        let header = NSMenuItem(title: "Seeubot", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header); headerItem = header
        menu.addItem(.separator())

        // 系统 API（行级）：NSMenuItem 是 AppKit 菜单中的一项。
        let upd = NSMenuItem(title: "Check for Updates…", action: #selector(openReleases), keyEquivalent: "")
        upd.target = self; menu.addItem(upd); updateItem = upd
        menu.addItem(.separator())

        // 系统 API（行级）：NSMenuItem 是 AppKit 菜单中的一项。
        let hang = NSMenuItem(title: "Hanging pill", action: #selector(setHanging), keyEquivalent: "")
        hang.target = self; menu.addItem(hang); hangingItem = hang
        // 系统 API（行级）：NSMenuItem 是 AppKit 菜单中的一项。
        let sides = NSMenuItem(title: "Bar", action: #selector(setSides), keyEquivalent: "")
        sides.target = self; menu.addItem(sides); sidesItem = sides
        menu.addItem(.separator())

        // 系统 API（行级）：NSMenuItem 是 AppKit 菜单中的一项。
        let vis = NSMenuItem(title: "Hide widget", action: #selector(toggleVisibility), keyEquivalent: "h")
        vis.target = self; menu.addItem(vis); visItem = vis
        menu.addItem(.separator())

        // 系统 API（行级）：NSMenuItem 是 AppKit 菜单中的一项。
        let gh = NSMenuItem(title: "Homepage…", action: #selector(openHomepage), keyEquivalent: "")
        gh.target = self; menu.addItem(gh)
        // 系统 API（行级）：NSMenuItem 是 AppKit 菜单中的一项。
        let quit = NSMenuItem(title: "Quit Seeubot", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    /// 切到“刘海下方胶囊”形态。
    @objc private func setHanging() { store.mode = .hanging; ensureVisible() }
    /// 切到“刘海两侧 bar”形态。
    @objc private func setSides() { store.mode = .sides; ensureVisible() }
    @objc private func openHomepage() {
        // 系统 API（行级）：NSWorkspace.shared.open 调用系统默认方式打开 URL 或文件。
        if let u = URL(string: Self.homepage) { NSWorkspace.shared.open(u) }
    }
    // 系统 API（行级）：NSApp 是当前 AppKit 应用的快捷全局对象。
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleVisibility() {
        widgetVisible.toggle()
        if widgetVisible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }
    private func ensureVisible() {
        if !widgetVisible { widgetVisible = true; panel.orderFrontRegardless() }
    }

    /// Pop up the same control menu from the in-widget "⋯" button — a notch-proof
    /// way to reach Quit even if the menu-bar icon is hidden behind the notch.
    private func showControlMenu() {
        guard let menu = statusItem?.menu else { return }
        // 系统 API（行级）：NSEvent.mouseLocation 读取全局鼠标坐标。
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: - Placement

    /// 优先选择带刘海的屏幕；没有刘海时退回主屏。
    private static func targetScreen() -> NSScreen? {
        // 系统 API（行级）：NSScreen 提供当前屏幕列表和主屏信息。
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// 把透明大面板固定到屏幕顶部中央，内部 SwiftUI 再决定胶囊/卡片的位置。
    private func position(on screen: NSScreen?) {
        guard let screen else { return }
        let f = screen.frame
        let x = f.midX - Dim.panelWidth / 2
        // Top edge flush with the screen top so the widget merges with the notch.
        let y = f.maxY - Dim.panelHeight
        panel.setFrame(NSRect(x: x, y: y, width: Dim.panelWidth, height: Dim.panelHeight),
                       display: true)
    }

    /// 屏幕参数变化时重新测量 notch，并把窗口挪回正确位置。
    @objc private func screensChanged() {
        let screen = Self.targetScreen()
        store.updateMetrics(NotchMetrics.measure(screen))
        position(on: screen)
    }

    // MARK: - Hover tracking (poll the cursor; reliable for a passive overlay)

    /// 用 0.1s 轮询鼠标位置判断展开/收起。透明 click-through 窗口下这比 enter/leave 更稳定。
    private func startHoverTracking() {
        // 系统 API（行级）：Timer 是系统定时器，用于周期性执行闭包。
        let t = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            // 系统 API（行级）：MainActor.assumeIsolated 告诉编译器当前代码在主线程上下文。
            MainActor.assumeIsolated { self?.updateHover() }
        }
        // 系统 API（行级）：RunLoop.main.add 把 Timer 加入主运行循环。
        RunLoop.main.add(t, forMode: .common)
        hoverTimer = t
    }

    /// 根据鼠标是否在热区内，更新 `store.hover`；这个值会驱动胶囊展开成 dashboard。
    private func updateHover() {
        // 系统 API（行级）：NSEvent.mouseLocation 读取全局鼠标坐标。
        let mouse = NSEvent.mouseLocation                     // global, bottom-left origin
        let pf = panel.frame
        let m = store.metrics

        // Collapsed hot-zone depends on the form (non-notched Macs are always "flat").
        let collapsed: NSRect
        if !m.hasNotch || store.mode == .sides {
            // the whole bar, flush at the top.
            let w = SidesBar.width(m)
            let h = m.menuBarHeight
            collapsed = NSRect(x: pf.midX - w / 2, y: pf.maxY - h - 6, width: w, height: h + 6)
        } else {
            // the notch-width pill, just below the notch line.
            let pillTopY = pf.maxY - m.menuBarHeight
            collapsed = NSRect(x: pf.midX - m.notchWidth / 2 - 8,
                               y: pillTopY - Dim.pillHeight - 6,
                               width: m.notchWidth + 16,
                               height: Dim.pillHeight + 6)
        }

        // Expanded target: the WHOLE panel rect (+ a little). Because the card can be
        // anywhere inside the panel, this guarantees the widget only collapses once the
        // cursor truly leaves it — never while reading the bottom of the dashboard.
        let expanded = pf.insetBy(dx: -6, dy: -6)

        // `expanded` ⊇ `collapsed` (the pill lives inside the panel), so no oscillation.
        let active = store.hover ? expanded : collapsed
        let inside = active.contains(mouse)

        // Let clicks fall through to whatever is under the (mostly transparent) panel
        // unless the cursor is actually over the widget. Hover itself is polled here,
        // so ignoring mouse events while collapsed costs us nothing.
        panel.ignoresMouseEvents = !inside
        if inside != store.hover {
            store.hover = inside
            if ProcessInfo.processInfo.environment["SEEUBOT_DEBUG"] != nil {
                // 系统 API（行级）：FileHandle 读写文件句柄或标准输出/错误。
                FileHandle.standardError.write(
                    "hover=\(inside) mouse=\(Int(mouse.x)),\(Int(mouse.y))\n"
                        .data(using: .utf8)!)
            }
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    /// 每次菜单弹出前刷新标题、形态勾选状态和更新提示。
    func menuNeedsUpdate(_ menu: NSMenu) {
        let s = store.stats
        headerItem?.title = "Seeubot · \(s.totalWorking) working · \(s.totalIdle) idle"

        // The form switch only makes sense on a notched Mac.
        let notch = store.metrics.hasNotch
        hangingItem?.isHidden = !notch
        sidesItem?.isHidden = !notch
        hangingItem?.state = store.mode == .hanging ? .on : .off
        sidesItem?.state = store.mode == .sides ? .on : .off

        visItem?.title = widgetVisible ? "Hide widget" : "Show widget"

        if let tag = store.updateAvailable {
            updateItem?.title = "Update available: \(tag) — click to update"
        } else {
            updateItem?.title = "Up to date · v\(Updater.currentVersion)"
        }
    }
}
