#if DEBUG
import AppKit

/// Optional diagnostics for an isolated fixture. Cached drawing is not a compositor screenshot.
@MainActor
enum DesignSnapshot {
    private static var scheduled = false

    static func captureIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard !scheduled,
              args.contains("-design-preview"),
              Bundle.main.bundleIdentifier?.hasPrefix("be.spatie.daydreaming.preview") == true,
              let index = args.firstIndex(of: "-snapshot-to"), args.indices.contains(index + 1) else { return }
        scheduled = true
        let directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        let stateIndex = args.firstIndex(of: "-design-preview")!
        var state = args[stateIndex + 1]
        if let settings = args.firstIndex(of: "-preview-settings"), args.indices.contains(settings + 1) {
            state = "settings-" + args[settings + 1]
        } else if let presentation = args.firstIndex(of: "-preview-presentation"), args.indices.contains(presentation + 1) {
            state += "-" + args[presentation + 1]
        } else if args.contains("-preview-minimum") {
            state += "-minimum"
        }
        let name = state
        Task {
            var capturedWindow: NSWindow?
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(500))
                let window = args.contains("-preview-settings")
                    ? NSApp.windows.first(where: { $0.identifier?.rawValue == "daydreaming.settings" && $0.isVisible })
                    : NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })
                if let window {
                    capturedWindow = window
                    break
                }
            }
            guard let window = capturedWindow, let view = window.contentView else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            write(view, to: directory.appendingPathComponent("cached-\(name).png"))
            if let sheet = window.attachedSheet, let content = sheet.contentView {
                write(content, to: directory.appendingPathComponent("cached-\(name)-sheet.png"))
            }
        }
    }

    private static func write(_ view: NSView, to url: URL) {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        bitmap.size = bounds.size
        view.cacheDisplay(in: bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
#endif
