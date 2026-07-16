import SwiftUI
import AppKit

// 系统 API 速览：
// - ImageRenderer：把 SwiftUI View 离屏渲染成 NSImage。
// - NSImage / NSBitmapImageRep：AppKit 图片类型和位图编码工具，用来保存 PNG。
// - @ViewBuilder：根据 form 返回不同预览 View。
// - ZStack / VStack / Rectangle / LinearGradient：SwiftUI 基础布局和背景绘制。
// - FileHandle.standardError.write：向命令行输出渲染日志。
// - URL(fileURLWithPath:) / Data.write：把 PNG 数据写入文件。
/// Off-screen rendering of the widget to PNGs (via `ImageRenderer`), used for
/// design iteration without needing screen-recording permission. The backdrop
/// simulates the desktop + menu bar + physical notch so the merge is visible.
@MainActor
enum RenderPreview {

    static func run(stats: DashStats, metrics: NotchMetrics, dir: String) {
        // Measure the real dashboard height so we can size the panel correctly.
        // 系统 API（行级）：ImageRenderer 把 SwiftUI View 离屏渲染成图片。
        let r = ImageRenderer(content: DashboardBody(stats: stats, loaded: true))
        if let sz = r.nsImage?.size {
            let cardTotal = metrics.notchHeight + sz.height
            // 系统 API（行级）：FileHandle 读写文件句柄或标准输出/错误。
            FileHandle.standardError.write(
                "dashboard=\(Int(sz.width))x\(Int(sz.height))pt  cardTotal(incl notch)=\(Int(cardTotal))pt  panelHeight=\(Int(Dim.panelHeight))pt\n"
                    .data(using: .utf8)!)
        }
        save(scene(stats: stats, metrics: metrics, form: .hanging),
             to: "\(dir)/collapsed_hanging.png")
        save(scene(stats: stats, metrics: metrics, form: .sides),
             to: "\(dir)/collapsed_sides.png")
        save(scene(stats: stats, metrics: metrics, form: .expanded),
             to: "\(dir)/expanded.png")
        save(scene(stats: .empty, metrics: metrics, form: .expanded),
             to: "\(dir)/expanded_empty.png")

        // Non-notched Mac: flat continuous bar (no center gap).
        let flat = NotchMetrics(hasNotch: false, notchWidth: 0, notchHeight: 0,
                                menuBarHeight: 24, screenWidth: metrics.screenWidth)
        save(scene(stats: stats, metrics: flat, form: .sides), to: "\(dir)/collapsed_flat.png")
    }

    private enum Form { case hanging, sides, expanded }

    @ViewBuilder
    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private static func widget(stats: DashStats, metrics: NotchMetrics, form: Form) -> some View {
        switch form {
        case .sides:
            island(width: SidesBar.width(metrics), corner: Dim.barCorner, topPad: 0, metrics: metrics) {
                SidesBar(stats: stats, metrics: metrics)
            }
        case .hanging:
            island(width: metrics.notchWidth, corner: Dim.pillCorner, topPad: metrics.notchHeight, metrics: metrics) {
                CollapsedPill(stats: stats, metrics: metrics)
            }
        case .expanded:
            island(width: Dim.cardWidth, corner: Dim.cardCorner, topPad: metrics.notchHeight, metrics: metrics) {
                DashboardBody(stats: stats, loaded: true, mode: .hanging)
            }
        }
    }

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private static func island<Content: View>(width: CGFloat, corner: CGFloat, topPad: CGFloat,
                                              metrics: NotchMetrics,
                                              // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
                                              @ViewBuilder _ content: () -> Content) -> some View {
        content()
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
            .overlay(IslandShape(bottomRadius: corner).stroke(Color.white.opacity(0.1), lineWidth: 1))
            // 系统 API（行级）：.clipShape 按指定形状裁剪视图。
            .clipShape(IslandShape(bottomRadius: corner))
    }

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private static func scene(stats: DashStats, metrics: NotchMetrics, form: Form) -> some View {
        let screenW: CGFloat = 900
        // 系统 API（行级）：ZStack 叠放子视图。
        return ZStack(alignment: .top) {
            // 系统 API（行级）：LinearGradient 创建线性渐变。
            LinearGradient(colors: [Color(red: 0.18, green: 0.28, blue: 0.42),
                                    Color(red: 0.10, green: 0.12, blue: 0.20)],
                           startPoint: .top, endPoint: .bottom)
            // 系统 API（行级）：VStack 纵向排列子视图。
            VStack(spacing: 0) {
                // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
                Rectangle().fill(Color.black.opacity(0.5)).frame(height: metrics.notchHeight)
                // 系统 API（行级）：Spacer 是 SwiftUI 弹性空白，占据剩余空间。
                Spacer()
            }
            widget(stats: stats, metrics: metrics, form: form)
            // physical notch cutout drawn on top
            // 系统 API（行级）：VStack 纵向排列子视图。
            VStack(spacing: 0) {
                // 系统 API（行级）：Rectangle 是 SwiftUI 矩形形状。
                Rectangle().fill(.black)
                    // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
                    .frame(width: metrics.notchWidth, height: metrics.notchHeight)
                // 系统 API（行级）：Spacer 是 SwiftUI 弹性空白，占据剩余空间。
                Spacer()
            }
        }
        // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
        .frame(width: screenW, height: form == .expanded ? 620 : 150)
    }

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    private static func save(_ view: some View, to path: String) {
        // 系统 API（行级）：ImageRenderer 把 SwiftUI View 离屏渲染成图片。
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              // 系统 API（行级）：NSBitmapImageRep 把 NSImage 转成可写入 PNG 的位图表示。
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            // 系统 API（行级）：FileHandle 读写文件句柄或标准输出/错误。
            FileHandle.standardError.write("render failed for \(path)\n".data(using: .utf8)!)
            return
        }
        // 系统 API（行级）：URL 构造系统 URL 对象。
        try? png.write(to: URL(fileURLWithPath: path))
        // 系统 API（行级）：FileHandle 读写文件句柄或标准输出/错误。
        FileHandle.standardError.write("wrote \(path)\n".data(using: .utf8)!)
    }
}
