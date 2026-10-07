import ImageIO
import SwiftUI

/// Decode once per URL, away from the main actor, instead of on every status update.
struct WallpaperPreview: View {
    let url: URL?
    let label: String
    var fullBleed = false
    var fillsFrame = false
    var softBackdrop = false
    var backdropOnly = false
    var animatesBackdrop = false
    var displayAspectRatio: CGFloat?
    var preloadURLs: [URL] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onAspectRatioChange: ((Double) -> Void)?
    var onImageDisplayed: ((URL?) -> Void)?
    @State private var image: CGImage?
    @State private var loadedURL: URL?

    var body: some View {
        GeometryReader { geometry in
            let canvas = ZStack {
                if displayAspectRatio == nil || image == nil || backdropOnly {
                    Color(nsColor: .windowBackgroundColor)
                }
                if let image {
                    if backdropOnly {
                        SoftArtworkBackdrop(image: image)
                    } else if let ratio = displayAspectRatio {
                        ScreenFramedArtwork(image: image, displayAspectRatio: ratio)
                            .id(loadedURL).transition(.opacity)
                    } else {
                        if softBackdrop {
                            SoftArtworkBackdrop(image: image)
                        } else if !softBackdrop { Color.black }
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: fillsFrame ? .fill : .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .id(loadedURL).transition(.opacity)
                    }
                } else {
                    LivingBackdrop(animates: animatesBackdrop)
                    if !backdropOnly {
                        ContentUnavailableView("Your Picture Goes Here", systemImage: "photo.artframe",
                                               description: Text("Choose a photo, illustration, or wallpaper."))
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            if displayAspectRatio != nil && image != nil && !backdropOnly {
                canvas
            } else {
                canvas.clipShape(.rect(cornerRadius: fullBleed ? 0 : 16))
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .task(id: url) {
            guard let url else {
                image = nil; loadedURL = nil; onImageDisplayed?(nil); return
            }
            let result = await WallpaperThumbnailCache.shared.thumbnail(at: url)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                image = result?.image
                loadedURL = url
            }
            if let result { onAspectRatioChange?(Double(result.image.width) / Double(result.image.height)) }
            onImageDisplayed?(result == nil ? nil : url)
        }
        .task(id: preloadURLs) {
            for url in preloadURLs {
                guard !Task.isCancelled else { return }
                _ = await WallpaperThumbnailCache.shared.thumbnail(at: url)
            }
        }
    }
}

/// A still, soft echo of the picture. No moving ribbons around ready artwork.
private struct SoftArtworkBackdrop: View {
    let image: CGImage
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if !reduceTransparency && contrast != .increased {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 60).opacity(0.12)
                }
            }.clipped()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Both selection surfaces show the same centered fill as the desktop.
struct ScreenFramedArtwork: View {
    let image: CGImage
    let displayAspectRatio: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let layout = ScreenArtworkLayout(imageSize: CGSize(width: image.width, height: image.height),
                                             viewportSize: geometry.size, displayAspectRatio: displayAspectRatio)
            ZStack {
                if let rect = layout.imageRect {
                    Image(decorative: image, scale: 1).resizable()
                        .frame(width: rect.width, height: rect.height)
                        .frame(width: layout.frameSize.width, height: layout.frameSize.height)
                        .clipShape(.rect(cornerRadius: 10))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.26 : 0.12), radius: 18, y: 8)
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ScreenArtworkLayout {
    let frameSize: CGSize
    let imageRect: CGRect?

    init(imageSize: CGSize, viewportSize: CGSize, displayAspectRatio: CGFloat) {
        let ratio = displayAspectRatio.isFinite && displayAspectRatio > 0 ? displayAspectRatio : 16.0 / 9.0
        let available = CGSize(width: max(1, viewportSize.width), height: max(1, viewportSize.height))
        let height = min(available.height, available.width / ratio)
        frameSize = CGSize(width: height * ratio, height: height)
        imageRect = WallpaperController.fillRect(imageSize: imageSize, screenSize: frameSize)
    }
}

private actor WallpaperThumbnailCache {
    struct Thumbnail: Sendable {
        let image: CGImage
    }
    static let shared = WallpaperThumbnailCache()
    private var images: [URL: Thumbnail] = [:]
    private var order: [URL] = []
    private var inFlight: [URL: Task<Thumbnail?, Never>] = [:]
    private var decodeTail: Task<Thumbnail?, Never>?

    func thumbnail(at url: URL) async -> Thumbnail? {
        if let image = images[url] { return image }
        if let task = inFlight[url] { return await task.value }
        let previous = decodeTail
        let task = Task.detached(priority: .userInitiated) {
            _ = await previous?.value
            guard let image = Self.decode(at: url) else { return nil as Thumbnail? }
            return Thumbnail(image: image)
        }
        inFlight[url] = task
        decodeTail = task
        let result = await task.value
        inFlight[url] = nil
        guard let result else { return nil }
        images[url] = result
        order.removeAll { $0 == url }
        order.append(url)
        while order.count > 8 { images.removeValue(forKey: order.removeFirst()) }
        return result
    }

    nonisolated private static func decode(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_000,
        ] as CFDictionary)
    }
}
