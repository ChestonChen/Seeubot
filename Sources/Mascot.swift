import SwiftUI

// 系统 API 速览：
// - TimelineView(.animation)：按动画帧刷新 Canvas。
// - Canvas / GraphicsContext：SwiftUI 的 2D 绘图 API，用来手绘机器人。
// - Path：绘制圆角矩形、曲线、眼睛、嘴巴、星星等路径。
// - CGPoint / CGSize / CGRect：几何类型，表示点、尺寸和矩形。
// - Color / Gradient：颜色和渐变。
// - Text：在 Canvas 里画 sleeping 状态的 “z”。
// - sin / floor / abs / min / max：标准数学函数，用来生成眨眼、呼吸、跳动等动画曲线。
enum Mood {
    case excited   // sessions actively working
    case idle      // sessions open but quiet
    case sleeping  // nothing running

    static func from(_ s: DashStats) -> Mood {
        // UI 情绪只由整体 session 状态决定：有 working 最活跃，有 live 但无 working 则 idle。
        if s.totalWorking > 0 { return .excited }
        if s.totalLive > 0 { return .idle }
        return .sleeping
    }

    var bulb: Color {
        switch self {
        case .excited: return Palette.working
        case .idle:    return Palette.idle
        case .sleeping: return Palette.sleepy
        }
    }
    /// Overall liveliness multiplier for the animations.
    var energy: Double {
        switch self { case .excited: return 1.0; case .idle: return 0.5; case .sleeping: return 0.15 }
    }
}

/// Seeubot 小机器人：用 Canvas 手绘，不依赖图片资源。
/// 它会根据 Mood 做眨眼、呼吸、摇头、打盹、工作时嘴巴 chatter 和星星效果。
// 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
struct MascotView: View {
    var mood: Mood
    var size: CGFloat = 46

    // 系统 API（行级）：View 是 SwiftUI 组件协议，body 描述界面内容。
    var body: some View {
        // 系统 API（行级）：TimelineView 按时间刷新视图，常用于动画。
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            // 系统 API（行级）：Canvas 是 SwiftUI 2D 绘图区域。
            Canvas { ctx, canvas in
                draw(ctx: &ctx, canvas: canvas, t: t)
            }
            // 系统 API（行级）：.frame 设置视图期望宽高或对齐方式。
            .frame(width: size * 1.6, height: size * 1.7)
        }
        // 系统 API（行级）：.accessibilityHidden 控制是否暴露给辅助功能。
        .accessibilityHidden(true)
    }

    // Deterministic pseudo-random in 0..1 for a given "slot" (no Math.random so the
    // animation stays stable frame-to-frame).
    private func hash01(_ n: Double) -> Double {
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        let v = sin(n * 12.9898) * 43758.5453
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        return v - floor(v)
    }
    // 0→1→0 hump over a 0..1 phase.
    // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
    private func hump(_ p: Double) -> Double { p <= 0 || p >= 1 ? 0 : sin(p * .pi) }

    /// Canvas 的主绘制函数。所有表情和动画都由当前时间 `t` 和 mood 算出来。
    // 系统 API（行级）：GraphicsContext 是 Canvas 的绘图上下文。
    private func draw(ctx: inout GraphicsContext, canvas: CGSize, t: Double) {
        let s = size
        let cx = canvas.width / 2
        let cy = canvas.height * 0.56
        let e = mood.energy

        // 每 4.2 秒一个动作槽，确定性随机选择跳一下或扭一下。
        let slotLen = 4.2
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        let slot = floor(t / slotLen)
        let sp = (t - slot * slotLen) / slotLen          // 0..1 within the slot
        let r = hash01(slot)
        let doHop    = mood != .sleeping && r < 0.30
        let doWiggle = mood != .sleeping && r >= 0.30 && r < 0.58
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        let hopP     = doHop ? hump(min(1, sp * 3)) : 0            // quick hop early in the slot
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        let wiggleP  = doWiggle ? hump(min(1, sp * 2.2)) : 0

        // 基础动作：呼吸、上下浮动、跳跃时拉伸/压扁、轻微倾斜。
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        let bob = CGFloat(sin(t * 1.9) * 0.02 * (0.5 + e)) * s - CGFloat(hopP) * s * 0.16
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        let breathe = 1 + CGFloat(sin(t * 1.9)) * 0.02
        let stretch = 1 + CGFloat(hopP) * 0.10                     // taller on the way up
        let squashX = 1 / (1 + CGFloat(hopP) * 0.06)
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        var tilt = CGFloat(sin(t * 0.8)) * 0.05 * CGFloat(0.4 + e) // gentle sway
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        tilt += CGFloat(sin(sp * .pi * 6)) * 0.16 * CGFloat(wiggleP)

        let headCenter = CGPoint(x: cx, y: cy + bob)

        // ---- transform: everything below is drawn relative to the head center ----
        var g = ctx
        g.translateBy(x: headCenter.x, y: headCenter.y)
        g.rotate(by: .radians(Double(tilt)))
        g.scaleBy(x: breathe * squashX, y: breathe * stretch)

        let hw = s * 0.92, hh = s * 0.88
        let headRect = CGRect(x: -hw / 2, y: -hh / 2, width: hw, height: hh)
        let corner = s * 0.34
        let eyeColor = Color(red: 0.13, green: 0.15, blue: 0.24)

        // ---------- Antenna (sways, bulb bobs & pulses) ----------
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        let sway = CGFloat(sin(t * 1.6 + 0.6)) * s * 0.05 * CGFloat(0.5 + e)
        let base = CGPoint(x: 0, y: -hh / 2)
        let tip = CGPoint(x: sway, y: -hh / 2 - s * 0.26 - CGFloat(hopP) * s * 0.03)
        // 系统 API（行级）：Path 是 SwiftUI 矢量路径，用来画线条/形状。
        var stalk = Path()
        stalk.move(to: base)
        stalk.addQuadCurve(to: tip, control: CGPoint(x: sway * 0.5, y: -hh / 2 - s * 0.14))
        // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
        g.stroke(stalk, with: .color(Color.white.opacity(0.55)),
                 style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round))

        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        let pulse = 0.55 + 0.45 * sin(t * (mood == .excited ? 7 : 2.4))
        let bulbR = s * 0.075 * (1 + 0.22 * CGFloat(pulse) * CGFloat(e))
        // 系统 API（行级）：Path 是 SwiftUI 矢量路径，用来画线条/形状。
        g.fill(Path(ellipseIn: CGRect(x: tip.x - bulbR * 2.6, y: tip.y - bulbR * 2.6,
                                      width: bulbR * 5.2, height: bulbR * 5.2)),
               // 系统 API（行级）：Gradient 定义渐变颜色序列。
               with: .radialGradient(Gradient(colors: [mood.bulb.opacity(0.6 * pulse), .clear]),
                                     center: tip, startRadius: 0, endRadius: bulbR * 2.6))
        // 系统 API（行级）：Path 是 SwiftUI 矢量路径，用来画线条/形状。
        g.fill(Path(ellipseIn: CGRect(x: tip.x - bulbR, y: tip.y - bulbR, width: bulbR * 2, height: bulbR * 2)),
               with: .color(mood.bulb))

        // ---------- Head ----------
        // 系统 API（行级）：Path 是 SwiftUI 矢量路径，用来画线条/形状。
        let headPath = Path(roundedRect: headRect, cornerRadius: corner)
        // 系统 API（行级）：.fill 用颜色或渐变填充形状。
        g.fill(headPath, with: .linearGradient(
            // 系统 API（行级）：Gradient 定义渐变颜色序列。
            Gradient(colors: [Color(white: 0.97), Color(white: 0.82)]),
            startPoint: CGPoint(x: 0, y: headRect.minY), endPoint: CGPoint(x: 0, y: headRect.maxY)))
        // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
        g.stroke(headPath, with: .color(Color.white.opacity(0.9)), lineWidth: s * 0.02)
        // 系统 API（行级）：Path 是 SwiftUI 矢量路径，用来画线条/形状。
        g.fill(Path(roundedRect: CGRect(x: -hw / 2 + s * 0.12, y: headRect.minY + s * 0.07,
                                        width: hw - s * 0.24, height: s * 0.19), cornerRadius: s * 0.1),
               // 系统 API（行级）：Color 是 SwiftUI 颜色类型。
               with: .color(Color.white.opacity(0.5)))

        // ---------- Cheeks (breathing blush) ----------
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        let cheekR = s * (0.07 + 0.012 * CGFloat(0.5 + 0.5 * sin(t * 2.6)) * CGFloat(e))
        let cheekY = s * 0.15
        for dx in [-s * 0.29, s * 0.29] {
            // 系统 API（行级）：Path 是 SwiftUI 矢量路径，用来画线条/形状。
            g.fill(Path(ellipseIn: CGRect(x: dx - cheekR, y: cheekY - cheekR, width: cheekR * 2, height: cheekR * 2)),
                   // 系统 API（行级）：.opacity 设置透明度。
                   with: .color(Color(red: 1.0, green: 0.55, blue: 0.62).opacity(0.45 + 0.15 * pulse)))
        }

        // ---------- Eyes (blink, glance around) ----------
        // wandering gaze
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        let look = CGPoint(x: CGFloat(sin(t * 0.9) * 0.5 + sin(t * 0.37) * 0.3) * s * 0.045 * CGFloat(0.4 + e),
                           // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
                           y: CGFloat(sin(t * 0.6 + 1) * 0.4) * s * 0.03 * CGFloat(0.4 + e))
        // blink: quick close roughly every 3.1s, with an occasional double-blink
        let bc = t.truncatingRemainder(dividingBy: 3.1)
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        var blink = bc < 0.14 ? (1 - abs(bc - 0.07) / 0.07) : 0
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        if hash01(floor(t / 3.1)) < 0.3 {   // double blink sometimes
            let bc2 = bc - 0.26
            // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
            if bc2 > 0, bc2 < 0.14 { blink = max(blink, 1 - abs(bc2 - 0.07) / 0.07) }
        }
        let eyeDX = s * 0.2, eyeY = -s * 0.02
        for dir in [-1.0, 1.0] {
            let ec = CGPoint(x: CGFloat(dir) * eyeDX + look.x, y: eyeY + look.y)
            if mood == .sleeping {
                // 系统 API（行级）：Path 是 SwiftUI 矢量路径，用来画线条/形状。
                var arc = Path()
                let rr = s * 0.1
                arc.addArc(center: CGPoint(x: ec.x, y: ec.y - rr * 0.2), radius: rr,
                           startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
                // 系统 API（行级）：.stroke 给形状描边。
                g.stroke(arc, with: .color(eyeColor), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round))
            } else {
                let wide: CGFloat = mood == .excited ? 1.12 : 1.0
                let eyeW = s * 0.15 * wide
                let eyeH = s * 0.23 * wide * (1 - 0.92 * CGFloat(blink))
                let er = CGRect(x: ec.x - eyeW / 2, y: ec.y - eyeH / 2, width: eyeW, height: eyeH)
                // 系统 API（行级）：Path 是 SwiftUI 矢量路径，用来画线条/形状。
                g.fill(Path(roundedRect: er, cornerRadius: eyeW * 0.5), with: .color(eyeColor))
                if blink < 0.4 {
                    let gr = s * 0.05
                    // 系统 API（行级）：Path 是 SwiftUI 矢量路径，用来画线条/形状。
                    g.fill(Path(ellipseIn: CGRect(x: ec.x - eyeW * 0.06 + look.x * 0.5,
                                                  y: ec.y - eyeH * 0.26, width: gr, height: gr)),
                           with: .color(.white))
                }
            }
        }

        // ---------- Mouth ----------
        let mouthY = s * 0.26
        switch mood {
        case .excited:
            // chatter: the open smile opens & closes like it's talking/typing
            // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
            let chatter = 0.45 + 0.55 * abs(sin(t * 9))
            let mw = s * 0.24, mh = s * (0.07 + 0.13 * chatter)
            let m = CGRect(x: -mw / 2, y: mouthY - mh / 2, width: mw, height: mh)
            // 系统 API（行级）：Path 是 SwiftUI 矢量路径，用来画线条/形状。
            g.fill(Path(roundedRect: m, cornerRadius: mh * 0.5), with: .color(eyeColor))
            let tw = mw * 0.5
            // 系统 API（行级）：Path 是 SwiftUI 矢量路径，用来画线条/形状。
            g.fill(Path(roundedRect: CGRect(x: -tw / 2, y: mouthY + mh * 0.04, width: tw, height: mh * 0.45),
                        cornerRadius: mh * 0.25), with: .color(Color(red: 1.0, green: 0.5, blue: 0.55)))
        case .idle:
            // 系统 API（行级）：Path 是 SwiftUI 矢量路径，用来画线条/形状。
            var smile = Path()
            let rr = s * 0.14
            smile.addArc(center: CGPoint(x: 0, y: mouthY - rr * 0.5), radius: rr,
                         startAngle: .degrees(30), endAngle: .degrees(150), clockwise: false)
            // 系统 API（行级）：.stroke 给形状描边。
            g.stroke(smile, with: .color(eyeColor), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round))
        case .sleeping:
            let mw = s * 0.12
            // 系统 API（行级）：.stroke 给形状描边。
            g.stroke(Path { p in p.move(to: CGPoint(x: -mw / 2, y: mouthY)); p.addLine(to: CGPoint(x: mw / 2, y: mouthY)) },
                     with: .color(eyeColor), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
        }

        // ---------- Sparkles (excited) — twinkle around the head, in canvas space ----------
        if mood == .excited {
            let spots: [(CGFloat, CGFloat, Double)] = [(-0.62, -0.30, 0), (0.64, -0.12, 0.5),
                                                       (-0.58, 0.28, 0.85), (0.60, 0.34, 0.3), (0.0, -0.66, 0.7)]
            for (dx, dy, ph) in spots {
                // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
                let tw = 0.5 + 0.5 * sin(t * 3.4 + ph * 6.28)
                guard tw > 0.15 else { continue }
                let p = CGPoint(x: cx + dx * s * 0.95, y: headCenter.y + dy * s * 0.95)
                // 系统 API（行级）：.opacity 设置透明度。
                drawSparkle(&ctx, at: p, r: s * 0.07 * CGFloat(tw), color: Palette.working.opacity(0.9 * tw))
            }
        }

        // ---------- zzz (sleeping) ----------
        if mood == .sleeping {
            let zt = t.truncatingRemainder(dividingBy: 2.8) / 2.8
            for i in 0..<3 {
                let phase = zt - Double(i) * 0.16
                guard phase > 0, phase < 1 else { continue }
                let fz = CGFloat(phase)
                let zx = headCenter.x + hw * 0.42 + fz * s * 0.3
                let zy = headCenter.y - hh * 0.4 - fz * s * 0.42
                var txt = ctx; txt.opacity = Double(1 - fz)
                // 系统 API（行级）：Text 是 SwiftUI 文本组件。
                txt.draw(Text("z").font(.system(size: s * (0.13 + 0.05 * Double(i)), weight: .heavy, design: .rounded))
                    // 系统 API（行级）：.opacity 设置透明度。
                    .foregroundColor(Palette.idle.opacity(0.9)), at: CGPoint(x: zx, y: zy))
            }
        }
    }

    /// A little 4-point sparkle (diamond star).
    // 系统 API（行级）：GraphicsContext 是 Canvas 的绘图上下文。
    private func drawSparkle(_ ctx: inout GraphicsContext, at p: CGPoint, r: CGFloat, color: Color) {
        // 系统 API（行级）：Path 是 SwiftUI 矢量路径，用来画线条/形状。
        var path = Path()
        let k = r * 0.34
        path.move(to: CGPoint(x: p.x, y: p.y - r))
        path.addQuadCurve(to: CGPoint(x: p.x + r, y: p.y), control: CGPoint(x: p.x + k, y: p.y - k))
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r), control: CGPoint(x: p.x + k, y: p.y + k))
        path.addQuadCurve(to: CGPoint(x: p.x - r, y: p.y), control: CGPoint(x: p.x - k, y: p.y + k))
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r), control: CGPoint(x: p.x - k, y: p.y - k))
        path.closeSubpath()
        // 系统 API（行级）：.fill 用颜色或渐变填充形状。
        ctx.fill(path, with: .color(color))
    }
}
