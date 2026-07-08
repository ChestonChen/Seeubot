import SwiftUI

/// Collapsed-only mascot runway. While work is active the bot glides across the
/// available track and gets a deterministic random prop action every few seconds.
struct WorkingMascotRunway: View {
    @Environment(\.displayScale) private var displayScale

    var mood: Mood
    var active: Bool
    var trackWidth: CGFloat
    var height: CGFloat
    var mascotSize: CGFloat
    var restingEdge: RestingEdge = .left

    enum RestingEdge {
        case left
        case right
    }

    private var mascotWidth: CGFloat { max(25, mascotSize * 1.6) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !active)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let travel = max(0, trackWidth - mascotWidth)
            let motionSpeed = 1.35
            let phase = active ? (0.5 + 0.5 * sin(t * motionSpeed)) : restingPhase
            let x = pixelAligned(CGFloat(phase) * travel)
            let y = pixelAligned(active ? CGFloat(sin(t * 2.9)) * 1.1 : 0)
            let direction: CGFloat = cos(t * motionSpeed) >= 0 ? 1 : -1
            let action = active ? WorkPropAction.pick(t) : .none

            ZStack(alignment: .leading) {
                if active {
                    propLayer(action: action, botX: x, phase: phase, direction: direction, t: t)
                }

                ZStack(alignment: .bottom) {
                    MascotView(mood: mood, size: mascotSize)
                        .frame(width: mascotWidth, height: height)
                        .clipped()

                    if active {
                        vehicleLayer(action: action, t: t)
                    }
                }
                .frame(width: mascotWidth, height: height)
                .compositingGroup()
                .offset(x: x, y: y)
            }
            .frame(width: trackWidth, height: height, alignment: .leading)
        }
    }

    private var restingPhase: Double {
        switch restingEdge {
        case .left: return 0
        case .right: return 1
        }
    }

    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        guard displayScale > 0 else { return value }
        return (value * displayScale).rounded() / displayScale
    }

    @ViewBuilder
    private func propLayer(action: WorkPropAction, botX: CGFloat, phase: Double,
                           direction: CGFloat, t: Double) -> some View {
        switch action {
        case .sparkTrail:
            sparkTrail(botX: botX, phase: phase, direction: direction, t: t)
        case .speedLines:
            speedParticles(botX: botX, phase: phase, direction: direction, t: t)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func vehicleLayer(action: WorkPropAction, t: Double) -> some View {
        switch action {
        case .sparkTrail:
            tinyHoverPad(t: t)
        case .speedLines:
            tinyRocketSkid(t: t)
        case .none:
            EmptyView()
        }
    }

    private func sparkTrail(botX: CGFloat, phase: Double, direction: CGFloat, t: Double) -> some View {
        let fade = CGFloat(edgeFade(phase))
        let anchorX = botX + (direction > 0 ? mascotWidth * 0.20 : mascotWidth * 0.80)

        return ZStack {
            ForEach(0..<5, id: \.self) { i in
                let lag = CGFloat(i) * 6.5 * fade
                let pulse = 0.55 + 0.45 * sin(t * 4.2 + Double(i))
                let x = clamped(anchorX - direction * lag, min: 4, max: trackWidth - 4)
                let y = height * (0.38 + 0.05 * CGFloat(sin(t * 2 + Double(i))))

                sparkleDot(size: 2.6 + CGFloat(pulse) * 1.8)
                    .foregroundStyle(Palette.working.opacity(Double(fade) * (0.25 + 0.55 * pulse)))
                    .position(x: x, y: y)
            }
        }
    }

    private func speedParticles(botX: CGFloat, phase: Double, direction: CGFloat, t: Double) -> some View {
        let fade = CGFloat(edgeFade(phase))
        let anchorX = botX + (direction > 0 ? mascotWidth * 0.16 : mascotWidth * 0.84)

        return ZStack {
            ForEach(0..<4, id: \.self) { i in
                let pulse = 0.5 + 0.5 * sin(t * 5.2 + Double(i) * 0.7)
                let lag = CGFloat(i) * 6 * fade
                let x = clamped(anchorX - direction * lag, min: 4, max: trackWidth - 4)
                Capsule()
                    .fill(Palette.working.opacity(0.22 + 0.38 * pulse))
                    .frame(width: 4.5, height: 2.4)
                    .scaleEffect(0.65 + CGFloat(pulse) * 0.35)
                    .opacity(Double(fade))
                    .position(x: x, y: height * (0.42 + CGFloat(i % 3) * 0.07))
            }
        }
    }

    private func sparkleDot(size: CGFloat) -> some View {
        ZStack {
            Capsule().frame(width: size * 0.42, height: size)
            Capsule().frame(width: size, height: size * 0.42)
        }
    }

    private func edgeFade(_ phase: Double) -> Double {
        min(1, max(0, min(phase, 1 - phase) / 0.16))
    }

    private func clamped(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minValue), maxValue)
    }

    private func tinyHoverPad(t: Double) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Capsule()
                .fill(Palette.idle.opacity(0.72))
                .frame(width: 21, height: 4)
                .shadow(color: Palette.idle.opacity(0.45), radius: 3, y: 1)
                .offset(y: -2 + CGFloat(sin(t * 5)) * 0.4)
        }
    }

    private func tinyRocketSkid(t: Double) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Capsule()
                .fill(Palette.working.opacity(0.78))
                .frame(width: 20, height: 5)
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.78, blue: 0.35).opacity(0.85))
                        .frame(width: 5, height: 5)
                        .offset(x: -2 - CGFloat(sin(t * 8)) * 1.2)
                }
                .offset(y: -2)
        }
    }
}

private enum WorkPropAction {
    case none
    case sparkTrail
    case speedLines

    static func pick(_ t: Double) -> WorkPropAction {
        let slotLength = 5.2
        let slot = floor(t / slotLength)
        let r = hash01(slot)
        return r < 0.5 ? .sparkTrail : .speedLines
    }

    private static func hash01(_ n: Double) -> Double {
        let v = sin(n * 12.9898) * 43758.5453
        return v - floor(v)
    }
}
