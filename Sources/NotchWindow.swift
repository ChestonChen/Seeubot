import AppKit

// 系统 API 速览：
// - NSPanel：macOS 的特殊窗口类型，适合做悬浮面板。
// - styleMask(.borderless / .nonactivatingPanel)：无边框且不抢焦点的窗口样式。
// - backgroundColor = .clear / isOpaque = false：让窗口透明，只显示 SwiftUI 画出来的内容。
// - collectionBehavior：控制窗口跨 Space、全屏辅助显示等行为。
// - CGWindowLevelForKey：获取系统窗口层级，这里让组件浮在菜单栏上方。
// - constrainFrameRect：AppKit 调整窗口位置前的钩子，这里直接返回原位置避免被推下菜单栏。
/// macOS 悬浮窗本体：透明、无边框、不抢焦点、浮在菜单栏上方。
/// SwiftUI 只负责画内容；真正让它“贴在刘海上”的是这个 NSPanel。
// 系统 API（行级）：NSPanel 是 AppKit 悬浮面板窗口。
final class NotchPanel: NSPanel {
    init(size: NSSize) {
        // 系统 API（行级）：NSPanel 是 AppKit 悬浮面板窗口。
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                 // the SwiftUI view draws its own shadow
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true         // click-through by default; the hover poll flips this on over the widget
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // Above the menu bar & status items so the widget overlays the notch.
        // (Set last — `isFloatingPanel`/style would otherwise reset the level.)
        // 系统 API（行级）：CGWindowLevelForKey 获取系统窗口层级常量。
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
    }

    // 不抢键盘焦点。点击仍会通过 FirstMouseHostingView 传给 SwiftUI。
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 不让 AppKit 自动把窗口推到菜单栏下方；我们需要顶部贴住屏幕顶边。
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

import SwiftUI

// SwiftUI 桥接 API：
// - NSHostingView：AppKit 承载 SwiftUI View 的桥梁，panel.contentView 最终挂的是它。
/// 让非激活窗口也能把第一次点击交给 SwiftUI，
/// 这样用户点切换按钮时不会先激活 app 再点第二次。
// 系统 API（行级）：NSHostingView 是 AppKit 承载 SwiftUI View 的桥。
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if ProcessInfo.processInfo.environment["SEEUBOT_DEBUG"] != nil {
            // 系统 API（行级）：FileHandle 读写文件句柄或标准输出/错误。
            FileHandle.standardError.write("HOSTING mouseDown \(event.locationInWindow)\n".data(using: .utf8)!)
        }
        super.mouseDown(with: event)
    }
}
