import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let homepage = "https://github.com/7757/Seeybot"

    private var panel: NotchPanel!
    private var store: StatsStore!
    private var hoverTimer: Timer?

    private var statusItem: NSStatusItem?
    private var widgetVisible = true
    private weak var headerItem: NSMenuItem?
    private weak var hangingItem: NSMenuItem?
    private weak var sidesItem: NSMenuItem?
    private weak var visItem: NSMenuItem?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let screen = Self.targetScreen()
        let metrics = NotchMetrics.measure(screen)
        store = StatsStore(metrics: metrics)
        store.onMenu = { [weak self] in self?.showControlMenu() }

        let root = NotchRootView(store: store)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: Dim.panelWidth, height: Dim.panelHeight)
        // Let clicks fall through transparent regions to whatever is underneath.
        hosting.autoresizingMask = [.width, .height]

        panel = NotchPanel(size: NSSize(width: Dim.panelWidth, height: Dim.panelHeight))
        panel.contentView = hosting
        position(on: screen)
        panel.orderFrontRegardless()

        // Reposition when displays change (dock a monitor, resolution change, sleep…).
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        startHoverTracking()
        setupMenuBar()
        scheduleUpdateChecks()
    }

    // MARK: - Update checks

    private var updateItem: NSMenuItem?

    private func scheduleUpdateChecks() {
        checkForUpdate()
        // re-check every 6 hours
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForUpdate() }
        }
        RunLoop.main.add(t, forMode: .common)
    }

    private func checkForUpdate() {
        Updater.checkLatest { tag in
            Task { @MainActor in self.store.updateAvailable = tag }
        }
    }

    @objc private func openReleases() { NSWorkspace.shared.open(Updater.releasesURL) }

    // MARK: - Menu bar (control surface: show/hide, switch form, quit)

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
                             accessibilityDescription: "Seeybot")
                     ?? NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "Seeybot") {
            img.isTemplate = true
            item.button?.image = img
        } else {
            item.button?.title = "◆"
        }

        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(title: "Seeybot", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header); headerItem = header
        menu.addItem(.separator())

        let upd = NSMenuItem(title: "Check for Updates…", action: #selector(openReleases), keyEquivalent: "")
        upd.target = self; menu.addItem(upd); updateItem = upd
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
        let quit = NSMenuItem(title: "Quit Seeybot", action: #selector(quit), keyEquivalent: "q")
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

    /// Pop up the same control menu from the in-widget "⋯" button — a notch-proof
    /// way to reach Quit even if the menu-bar icon is hidden behind the notch.
    private func showControlMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: - Placement

    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func position(on screen: NSScreen?) {
        guard let screen else { return }
        let f = screen.frame
        let x = f.midX - Dim.panelWidth / 2
        // Top edge flush with the screen top so the widget merges with the notch.
        let y = f.maxY - Dim.panelHeight
        panel.setFrame(NSRect(x: x, y: y, width: Dim.panelWidth, height: Dim.panelHeight),
                       display: true)
    }

    @objc private func screensChanged() {
        let screen = Self.targetScreen()
        store.updateMetrics(NotchMetrics.measure(screen))
        position(on: screen)
    }

    // MARK: - Hover tracking (poll the cursor; reliable for a passive overlay)

    private func startHoverTracking() {
        let t = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
        RunLoop.main.add(t, forMode: .common)
        hoverTimer = t
    }

    private func updateHover() {
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
            if ProcessInfo.processInfo.environment["SEEYBOT_DEBUG"] != nil {
                FileHandle.standardError.write(
                    "hover=\(inside) mouse=\(Int(mouse.x)),\(Int(mouse.y))\n"
                        .data(using: .utf8)!)
            }
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let s = store.stats
        headerItem?.title = "Seeybot · \(s.totalWorking) working · \(s.totalIdle) idle"

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
