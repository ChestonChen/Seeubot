import SwiftUI
import AppKit

// MARK: - Colors, gradients, fonts and layout constants for the whole widget.

enum Palette {
    static let notchBlack   = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let panelTop     = Color(red: 0.09, green: 0.09, blue: 0.12)
    static let panelBottom  = Color(red: 0.05, green: 0.05, blue: 0.07)

    static let ink          = Color.white
    static let inkDim       = Color.white.opacity(0.62)
    static let inkFaint     = Color.white.opacity(0.34)
    static let hairline     = Color.white.opacity(0.08)

    // Session states
    static let working      = Color(red: 0.24, green: 0.86, blue: 0.52)   // vivid green
    static let idle         = Color(red: 0.56, green: 0.65, blue: 1.00)   // periwinkle
    static let sleepy       = Color(red: 0.45, green: 0.47, blue: 0.58)

    // Tools
    static let claude       = Color(red: 0.98, green: 0.55, blue: 0.38)   // warm clay/coral
    static let claudeDeep   = Color(red: 0.92, green: 0.33, blue: 0.20)
    static let codex        = Color(red: 0.37, green: 0.90, blue: 0.80)   // mint/teal
    static let codexDeep    = Color(red: 0.09, green: 0.72, blue: 0.64)

    // Token buckets
    static let tOutput      = Color(red: 0.35, green: 0.87, blue: 0.53)
    static let tInput       = Color(red: 0.45, green: 0.68, blue: 1.00)
    static let tCacheCreate = Color(red: 0.72, green: 0.55, blue: 1.00)
    static let tCacheRead   = Color(red: 0.36, green: 0.45, blue: 0.55)

    static func tool(_ t: Tool) -> Color { t == .claude ? claude : codex }
    static func toolDeep(_ t: Tool) -> Color { t == .claude ? claudeDeep : codexDeep }

    static func gradient(_ t: Tool) -> LinearGradient {
        LinearGradient(colors: [tool(t), toolDeep(t)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum Typo {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Physical geometry of the display, measured at runtime. Handles both notched and
/// non-notched Macs — on a non-notched display `hasNotch == false` and `notchWidth == 0`
/// (no center gap), so the widget shows as one flat continuous bar.
struct NotchMetrics {
    var hasNotch: Bool
    var notchWidth: CGFloat      // width of the center gap to leave for the camera (0 if no notch)
    var notchHeight: CGFloat     // notch cutout height (safe-area inset); 0 if no notch
    var menuBarHeight: CGFloat   // full menu-bar height = top of the usable window area
    var screenWidth: CGFloat

    static func measure(_ screen: NSScreen?) -> NotchMetrics {
        guard let screen else {
            return NotchMetrics(hasNotch: false, notchWidth: 0, notchHeight: 0,
                                menuBarHeight: 24, screenWidth: 1440)
        }
        let full = screen.frame.width
        let hasNotch = screen.safeAreaInsets.top > 1
            && screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil

        var notchWidth: CGFloat = 0
        if hasNotch, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchWidth = max(120, full - l.width - r.width)
        }
        let notchHeight = hasNotch ? screen.safeAreaInsets.top : 0
        // Menu-bar bottom = where windows begin. This is the clearance the content needs.
        let menuBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)

        return NotchMetrics(hasNotch: hasNotch, notchWidth: notchWidth, notchHeight: notchHeight,
                            menuBarHeight: menuBar, screenWidth: full)
    }
}

/// Sizing for the collapsed pill and expanded card.
/// (Named `Dim`, not `Layout`, to avoid shadowing the SwiftUI `Layout` protocol.)
///
/// The widget hangs *just below* the notch (not over the menu bar) so it never
/// covers menu-bar tools. The collapsed pill is intentionally narrow, and the
/// expanded card is a strict superset of it so hover never oscillates.
enum Dim {
    static let panelWidth: CGFloat  = 440      // NSPanel width
    static let panelHeight: CGFloat = 540      // NSPanel height (holds the full dashboard)
    static let pillWidth: CGFloat   = 244      // collapsed pill width (compact, under the notch)
    static let pillHeight: CGFloat  = 34
    static let pillCorner: CGFloat  = 16
    static let cardWidth: CGFloat   = 384      // expanded dashboard width (> pillWidth)
    static let cardCorner: CGFloat  = 24
    static let dropBelowNotch: CGFloat = 2     // gap between the notch bottom and the pill

    // "sides" mode: one plain bar spanning the notch; the middle (notch width) is
    // left empty, content sits on either side. Height = menu bar (flush, no protrusion).
    static let barSideWidth: CGFloat = 84      // width of each side region flanking the notch
    static let barCorner: CGFloat = 10         // bottom-corner rounding of the plain bar
    static let flatBarWidth: CGFloat = 208     // width of the flat continuous bar on non-notched Macs
}
