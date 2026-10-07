import AppKit
import SwiftUI

/// Attach the real window without coupling its size to the picture's aspect ratio.
struct WindowViewport: NSViewRepresentable {
    let onWindowAvailable: (NSWindow) -> Void
    var onWindowMoved: ((CGPoint) -> Void)? = nil
    func makeNSView(context: Context) -> ViewportView { ViewportView() }
    func updateNSView(_ view: ViewportView, context: Context) {
        view.onWindowAvailable = onWindowAvailable
        view.onWindowMoved = onWindowMoved
        view.attach()
    }
    static func dismantleNSView(_ view: ViewportView, coordinator: ()) { view.removeObservers() }
    final class ViewportView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        var onWindowAvailable: ((NSWindow) -> Void)?
        var onWindowMoved: ((CGPoint) -> Void)?
        private weak var configuredWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []
        func removeObservers() {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
        }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); attach() }
        func attach() {
            guard let window else { return }
            onWindowAvailable?(window)
            guard configuredWindow !== window else { return }
            removeObservers()
            configuredWindow = window
            onWindowMoved?(window.frame.origin)
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    if let window { self?.onWindowMoved?(window.frame.origin) }
                }
            })
            let names: [Notification.Name] = [NSWindow.didChangeScreenNotification, NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                .NSProcessInfoPowerStateDidChange]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.attach() }
                })
            }
            window.contentAspectRatio = .zero
            let visible = window.screen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
            var size = WallpaperWindowGeometry.initialSize(visibleSize: visible)
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if AppRuntime.isPreview && args.contains("-design-preview") {
                if args.contains("-preview-minimum") { size = WallpaperWindowGeometry.minimumSize(visibleSize: visible) }
                if let index = args.firstIndex(of: "-preview-size"), args.indices.contains(index + 2),
                   let width = Double(args[index + 1]), let height = Double(args[index + 2]) {
                    size = CGSize(width: max(760, width), height: max(560, height))
                }
            }
            #endif
            window.setContentSize(size)
        }
    }
}
