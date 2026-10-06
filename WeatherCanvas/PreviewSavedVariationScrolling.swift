import AppKit
import SwiftUI

/// Wheel handling is limited to the artwork and removed with its hosting view.
struct PreviewSavedVariationScrolling: NSViewRepresentable {
    let enabled: Bool
    let onStep: @MainActor (Int) -> Void

    func makeNSView(context: Context) -> WheelView { WheelView() }
    func updateNSView(_ view: WheelView, context: Context) {
        view.enabled = enabled
        view.onStep = onStep
    }
    static func dismantleNSView(_ view: WheelView, coordinator: ()) { view.removeMonitor() }

    final class WheelView: NSView {
        var enabled = false
        var onStep: (@MainActor (Int) -> Void)?
        private var monitor: Any?
        private var policy = SavedVariationScrollPolicy()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self, self.enabled, let window = self.window, event.window === window,
                          window.isKeyWindow, window.attachedSheet == nil,
                          !self.isHiddenOrHasHiddenAncestor,
                          self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return false }
                    let delta = event.scrollingDeltaY
                    if let direction = self.policy.direction(delta: delta, precise: event.hasPreciseScrollingDeltas,
                                                              momentum: !event.momentumPhase.isEmpty,
                                                              began: event.phase.contains(.began), timestamp: event.timestamp) {
                        self.onStep?(direction)
                    }
                    return delta != 0
                }
                return handled ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            policy = SavedVariationScrollPolicy()
        }
    }
}
