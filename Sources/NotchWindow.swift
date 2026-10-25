import AppKit
final class NotchPanel: NSPanel {
    init(size: NSSize) {
        //contentRect用于设置窗口的初始位置和大小，styleMask用于设置窗口的样式，backing用于设置窗口的缓冲方式，defer用于设置窗口的延迟加载
        //.borderless用于设置窗口没有边框和标题栏，.nonactivatingPanel不会因为点击它切走app
        //backing是决定窗口在内存中怎么存放
        //  .buffered离屏渲染，在缓冲区画完上屏，.deferred用于设置窗口的延迟加载
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)//立刻分配渲染资源
        isOpaque = false//不透明
        backgroundColor = .clear//背景色为透明
        hasShadow = false//没有阴影
        isMovableByWindowBackground = false//不能移动窗口背景
        becomesKeyOnlyIfNeeded = true//只有在需要时才成为key窗口，不抢焦点
        hidesOnDeactivate = false//点击其他app时不会隐藏窗口 panel默认是true
        ignoresMouseEvents = true//不响应鼠标事件
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]//可以加入所有空间，固定在当前空间，全屏辅助，不参与切换焦点循环
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))//把窗口的**层级**抬到「弹出菜单那一层」
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    //不能成为主窗口，不能成为焦点窗口

    //系统在摆放窗口前会调用这个钩子，默认行为是「把窗口往下推、避开菜单栏」
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect//返回原始大小，不改变
    }
}
import SwiftUI
//NSHostingView SwiftUI 和 AppKit 之间的桥：把 SwiftUI 的 `View` 包装成一个 `NSView`，这样才能塞进窗口的 `contentView`
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }//用户点击第一下即事件生效
    override func mouseDown(with event: NSEvent) {
        if ProcessInfo.processInfo.environment["SEEUBOT_DEBUG"] != nil {
            FileHandle.standardError.write("HOSTING mouseDown \(event.locationInWindow)\n".data(using: .utf8)!)
        }
        super.mouseDown(with: event)//把事件交给swiftui上层处理
    }
}