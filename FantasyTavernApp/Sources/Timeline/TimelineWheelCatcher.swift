import SwiftUI
import AppKit

/// Forwards ⌘scroll wheel events to a callback. Returns true if the event was consumed.
struct TimelineWheelCatcher: NSViewRepresentable {
    let onCommandScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = WheelView()
        v.onWheel = { event in
            guard event.modifierFlags.contains(.command) else { return false }
            onCommandScroll(event.scrollingDeltaY)
            return true
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WheelView: NSView {
        var onWheel: ((NSEvent) -> Bool)?
        override var acceptsFirstResponder: Bool { true }
        override func scrollWheel(with event: NSEvent) {
            if onWheel?(event) == true { return }
            super.scrollWheel(with: event)
        }
    }
}
