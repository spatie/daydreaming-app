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
}
