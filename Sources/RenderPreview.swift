import SwiftUI
import AppKit

/// Off-screen rendering of the widget to PNGs (via `ImageRenderer`), used for
/// design iteration without needing screen-recording permission. The backdrop
/// simulates the desktop + menu bar + physical notch so the merge is visible.
@MainActor
enum RenderPreview {

    static func run(stats: DashStats, metrics: NotchMetrics, dir: String) {
        // Measure the real dashboard height so we can size the panel correctly.
        let r = ImageRenderer(content: DashboardBody(stats: stats, loaded: true))
        if let sz = r.nsImage?.size {
            let cardTotal = metrics.notchHeight + sz.height
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

    private static func island<Content: View>(width: CGFloat, corner: CGFloat, topPad: CGFloat,
                                              metrics: NotchMetrics,
                                              @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: width)
            .padding(.top, topPad)
            .background(
                IslandShape(bottomRadius: corner)
                    .fill(LinearGradient(colors: [Palette.notchBlack, Palette.panelBottom],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(IslandShape(bottomRadius: corner).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .clipShape(IslandShape(bottomRadius: corner))
    }

    private static func scene(stats: DashStats, metrics: NotchMetrics, form: Form) -> some View {
        let screenW: CGFloat = 900
        return ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.18, green: 0.28, blue: 0.42),
                                    Color(red: 0.10, green: 0.12, blue: 0.20)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                Rectangle().fill(Color.black.opacity(0.5)).frame(height: metrics.notchHeight)
                Spacer()
            }
            widget(stats: stats, metrics: metrics, form: form)
            // physical notch cutout drawn on top
            VStack(spacing: 0) {
                Rectangle().fill(.black)
                    .frame(width: metrics.notchWidth, height: metrics.notchHeight)
                Spacer()
            }
        }
        .frame(width: screenW, height: form == .expanded ? 620 : 150)
    }

    private static func save(_ view: some View, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("render failed for \(path)\n".data(using: .utf8)!)
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write("wrote \(path)\n".data(using: .utf8)!)
    }
}
