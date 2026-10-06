import CoreImage
import ImageIO
import SwiftUI

/// The expensive decode and first blur happen once, off-main, on a small image.
/// Only the screen-shaped artwork animates; editing controls remain still.
struct DreamingArtwork: View {
    let url: URL?
    let displayAspectRatio: CGFloat
    let isActive: Bool
    let lowPowerMode: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var image: CGImage?
    @State private var startedAt = Date.now

    var body: some View {
        GeometryReader { geometry in
            if let image {
                let layout = ScreenArtworkLayout(imageSize: CGSize(width: image.width, height: image.height),
                                                 viewportSize: geometry.size, displayAspectRatio: displayAspectRatio)
                if isActive && !reduceMotion && !lowPowerMode {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                        artwork(image, layout: layout, time: Float(timeline.date.timeIntervalSince(startedAt)))
                    }
                } else {
                    artwork(image, layout: layout, time: 0)
                }
            }
        }
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            guard let url else { return }
            let thumbnail = await DreamingThumbnailCache.shared.image(at: url)
            guard !Task.isCancelled else { return }
            image = thumbnail
            startedAt = .now
        }
    }

    @ViewBuilder private func artwork(_ image: CGImage, layout: ScreenArtworkLayout, time: Float) -> some View {
        if let rect = layout.imageRect {
            let picture = Image(decorative: image, scale: 1).resizable()
                .frame(width: rect.width, height: rect.height)
                .frame(width: layout.frameSize.width, height: layout.frameSize.height)
                .clipped()
            Group {
                if reduceTransparency || contrast == .increased {
                    picture.opacity(0.55)
                } else {
                    picture.layerEffect(ShaderLibrary.daydreamFlow(.float(time),
                                                                  .float2(layout.frameSize.width, layout.frameSize.height)),
                                        maxSampleOffset: CGSize(width: 40, height: 40))
                }
            }
            .clipShape(.rect(cornerRadius: 10))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private actor DreamingThumbnailCache {
    static let shared = DreamingThumbnailCache()
    private var images: [URL: CGImage] = [:]
    private var order: [URL] = []

    func image(at url: URL) async -> CGImage? {
        if let image = images[url] { return image }
        let result = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512,
                  ] as CFDictionary) else { return nil as CGImage? }
            let input = CIImage(cgImage: thumbnail)
            let blurred = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4])
                .cropped(to: input.extent)
            return CIContext().createCGImage(blurred, from: input.extent) ?? thumbnail
        }.value
        guard let result else { return nil }
        images[url] = result
        order.removeAll { $0 == url }
        order.append(url)
        while order.count > 4 { images.removeValue(forKey: order.removeFirst()) }
        return result
    }
}
