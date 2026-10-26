import AppKit
import Foundation

@MainActor
enum WallpaperController {
    static var desktopOptions: [NSWorkspace.DesktopImageOptionKey: Any] {
        [.imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
         .allowClipping: NSNumber(value: true)]
    }

    /// Centered proportional fill, matching the desktop options and artwork preview.
    nonisolated static func fillRect(imageSize: CGSize, screenSize: CGSize) -> CGRect? {
        guard imageSize.width > 0, imageSize.height > 0, screenSize.width > 0, screenSize.height > 0,
              imageSize.width.isFinite, imageSize.height.isFinite,
              screenSize.width.isFinite, screenSize.height.isFinite else { return nil }
        let scale = max(screenSize.width / imageSize.width, screenSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (screenSize.width - size.width) / 2, y: (screenSize.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    static func apply(_ imageURL: URL) throws {
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: desktopOptions)
        }
    }

    /// Replaces older Daydreaming wallpapers on the active Space, leaving pictures the user chose elsewhere alone.
    static func replaceOutdatedWallpapers(with imageURL: URL) throws {
        try replaceOutdated(on: NSScreen.screens, with: imageURL, owns: ImageStore.owns,
                            shown: { NSWorkspace.shared.desktopImageURL(for: $0) },
                            set: { try NSWorkspace.shared.setDesktopImageURL(imageURL, for: $0, options: desktopOptions) })
    }

    /// Tries every outdated display before reporting the first failure.
    nonisolated static func replaceOutdated<Screen>(on screens: [Screen], with imageURL: URL, owns: (String) -> Bool,
                                                    shown: (Screen) -> URL?, set: (Screen) throws -> Void) throws {
        var firstError: Error?
        for screen in screens where isOutdated(shown(screen), current: imageURL, owns: owns) {
            do { try set(screen) }
            catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }

    nonisolated static func isOutdated(_ shown: URL?, current: URL, owns: (String) -> Bool) -> Bool {
        guard let shown, shown.isFileURL else { return false }
        return shown.standardizedFileURL != current.standardizedFileURL && owns(shown.path)
    }

    static func isApplied(_ imageURL: URL) -> Bool {
        let screens = NSScreen.screens
        return !screens.isEmpty && screens.allSatisfy {
            NSWorkspace.shared.desktopImageURL(for: $0)?.standardizedFileURL == imageURL.standardizedFileURL
        }
    }
}
