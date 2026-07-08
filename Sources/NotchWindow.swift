import AppKit

/// A borderless, transparent, non-activating panel that floats over the notch and
/// never steals keyboard focus. It sits above the menu bar so the collapsed pill
/// visually merges with the physical notch.
final class NotchPanel: NSPanel {
    init(size: NSSize) {
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
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
    }

    // Non-activating: never steal focus. Taps still reach SwiftUI via the hosting
    // view's `acceptsFirstMouse` (see FirstMouseHostingView).
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Don't let AppKit push us below the menu bar — we want the top edge flush
    /// with the screen top so the pill hugs the notch.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

import SwiftUI

/// Hosting view that delivers clicks to SwiftUI even while the panel is inactive
/// (so the mode-toggle tap works without the widget ever stealing focus).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if ProcessInfo.processInfo.environment["SEEUBOT_DEBUG"] != nil {
            FileHandle.standardError.write("HOSTING mouseDown \(event.locationInWindow)\n".data(using: .utf8)!)
        }
        super.mouseDown(with: event)
    }
}
