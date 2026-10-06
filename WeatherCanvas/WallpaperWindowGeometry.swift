import Foundation

/// Editor chrome sets the window bounds; the picture never resizes the window.
enum WallpaperWindowGeometry {
    static func minimumSize(visibleSize: CGSize) -> CGSize {
        CGSize(width: min(760, max(1, visibleSize.width - 32)),
               height: min(560, max(1, visibleSize.height - 80)))
    }

    static func initialSize(visibleSize: CGSize) -> CGSize {
        let minimum = minimumSize(visibleSize: visibleSize)
        return CGSize(width: max(minimum.width, min(1000, visibleSize.width * 0.9)),
                      height: max(minimum.height, min(720, visibleSize.height - 80)))
    }
}
