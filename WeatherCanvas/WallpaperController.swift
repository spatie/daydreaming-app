import AppKit
import Foundation

@MainActor
enum WallpaperController {
    static func apply(_ imageURL: URL) throws {
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: [:])
        }
    }
}
