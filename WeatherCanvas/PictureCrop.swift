import CoreGraphics
import Foundation

/// A crop in the orientation-corrected picture, with positions measured from its top left.
struct PictureCrop: Codable, Equatable, Sendable {
    let normalizedRect: CGRect
    let usesOriginalRatio: Bool

    func matchesFraming(_ other: PictureCrop) -> Bool {
        let lhs = normalizedRect
        let rhs = other.normalizedRect
        return abs(lhs.minX - rhs.minX) < 0.002 && abs(lhs.minY - rhs.minY) < 0.002
            && abs(lhs.width - rhs.width) < 0.002 && abs(lhs.height - rhs.height) < 0.002
    }

    static func editingBaseline(savedCrop: PictureCrop?, imageSize: CGSize, displayAspectRatio: CGFloat) -> PictureCrop {
        (savedCrop ?? .original).constrained(imageSize: imageSize, targetAspectRatio: displayAspectRatio,
                                            usesOriginalRatio: false)
    }

    init(normalizedRect: CGRect, usesOriginalRatio: Bool = false) {
        let rect = normalizedRect.standardized
        let width = rect.width.isFinite ? min(1, max(0.001, rect.width)) : 1
        let height = rect.height.isFinite ? min(1, max(0.001, rect.height)) : 1
        let x = rect.minX.isFinite ? min(1 - width, max(0, rect.minX)) : 0
        let y = rect.minY.isFinite ? min(1 - height, max(0, rect.minY)) : 0
        self.normalizedRect = CGRect(x: x, y: y, width: width, height: height)
        self.usesOriginalRatio = usesOriginalRatio
    }

    enum Corner: String, CaseIterable, Identifiable {
        case topLeft, topRight, bottomLeft, bottomRight
        var id: String { rawValue }
        var title: String {
            switch self {
            case .topLeft: "Top left"
            case .topRight: "Top right"
            case .bottomLeft: "Bottom left"
            case .bottomRight: "Bottom right"
            }
        }
        var isLeft: Bool { self == .topLeft || self == .bottomLeft }
        var isTop: Bool { self == .topLeft || self == .topRight }
    }

    func moved(by translation: CGSize) -> PictureCrop {
        PictureCrop(normalizedRect: normalizedRect.offsetBy(dx: translation.width.isFinite ? translation.width : 0,
                                                           dy: translation.height.isFinite ? translation.height : 0),
                    usesOriginalRatio: usesOriginalRatio)
    }

    /// Resize a locked-aspect corner, keeping the opposite corner stationary.
    func resized(corner: Corner, translation: CGSize, imageSize: CGSize, targetAspectRatio: CGFloat,
                 minimumSize: CGSize = CGSize(width: 0.03, height: 0.03)) -> PictureCrop {
        guard imageSize.width > 0, imageSize.height > 0, targetAspectRatio > 0,
              imageSize.width.isFinite, imageSize.height.isFinite, targetAspectRatio.isFinite,
              translation.width.isFinite, translation.height.isFinite else { return self }
        let ratio = targetAspectRatio * imageSize.height / imageSize.width
        let anchor = CGPoint(x: corner.isLeft ? normalizedRect.maxX : normalizedRect.minX,
                             y: corner.isTop ? normalizedRect.maxY : normalizedRect.minY)
        let signX: CGFloat = corner.isLeft ? -1 : 1
        let signY: CGFloat = corner.isTop ? -1 : 1
        let moving = CGPoint(x: corner.isLeft ? normalizedRect.minX : normalizedRect.maxX,
                             y: corner.isTop ? normalizedRect.minY : normalizedRect.maxY)
        let dx = signX * (moving.x + translation.width - anchor.x)
        let dy = signY * (moving.y + translation.height - anchor.y)
        let availableX = corner.isLeft ? anchor.x : 1 - anchor.x
        let availableY = corner.isTop ? anchor.y : 1 - anchor.y
        let maximumHeight = min(availableY, availableX / ratio)
        let minimumHeight = min(maximumHeight, max(minimumSize.height, minimumSize.width / ratio))
        let projected = (ratio * dx * imageSize.width * imageSize.width + dy * imageSize.height * imageSize.height)
            / (ratio * ratio * imageSize.width * imageSize.width + imageSize.height * imageSize.height)
        let height = min(maximumHeight, max(minimumHeight, projected))
        let width = height * ratio
        return PictureCrop(normalizedRect: CGRect(x: corner.isLeft ? anchor.x - width : anchor.x,
                                                 y: corner.isTop ? anchor.y - height : anchor.y,
                                                 width: width, height: height), usesOriginalRatio: usesOriginalRatio)
    }

    func scaled(by scale: CGFloat, minimumSize: CGSize = CGSize(width: 0.03, height: 0.03)) -> PictureCrop {
        guard scale.isFinite, scale > 0 else { return self }
        let rect = normalizedRect
        let minimumScale = max(minimumSize.width / rect.width, minimumSize.height / rect.height)
        let maximumScale = min(1 / rect.width, 1 / rect.height)
        let factor = min(maximumScale, max(minimumScale, scale))
        let size = CGSize(width: rect.width * factor, height: rect.height * factor)
        return PictureCrop(normalizedRect: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                                 width: size.width, height: size.height), usesOriginalRatio: usesOriginalRatio)
    }

    func constrained(imageSize: CGSize, targetAspectRatio: CGFloat, usesOriginalRatio: Bool) -> PictureCrop {
        guard imageSize.width > 0, imageSize.height > 0, targetAspectRatio.isFinite, targetAspectRatio > 0 else { return self }
        let ratio = targetAspectRatio * imageSize.height / imageSize.width
        let width = min(normalizedRect.width, normalizedRect.height * ratio)
        let height = width / ratio
        return PictureCrop(normalizedRect: CGRect(x: normalizedRect.midX - width / 2, y: normalizedRect.midY - height / 2,
                                                 width: width, height: height), usesOriginalRatio: usesOriginalRatio)
    }

    init(imageSize: CGSize, targetAspectRatio: CGFloat, zoom: CGFloat = 1, offset: CGSize = .zero, usesOriginalRatio: Bool = false) {
        self.usesOriginalRatio = usesOriginalRatio
        guard imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0,
              targetAspectRatio.isFinite, targetAspectRatio > 0 else {
            normalizedRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            return
        }
        let imageAspect = imageSize.width / imageSize.height
        let magnification = zoom.isFinite ? min(4, max(1, zoom)) : 1
        let width = min(1, targetAspectRatio / imageAspect) / magnification
        let height = min(1, imageAspect / targetAspectRatio) / magnification
        let horizontal = offset.width.isFinite ? min(1, max(-1, offset.width)) : 0
        let vertical = offset.height.isFinite ? min(1, max(-1, offset.height)) : 0
        normalizedRect = CGRect(x: (1 - width) * (horizontal + 1) / 2,
                                y: (1 - height) * (vertical + 1) / 2,
                                width: width, height: height)
    }

    static let original = PictureCrop(imageSize: CGSize(width: 1, height: 1), targetAspectRatio: 1)

    struct Controls: Equatable {
        let zoom: CGFloat
        let offset: CGSize
    }

    func controls(imageSize: CGSize, targetAspectRatio: CGFloat) -> Controls {
        let base = PictureCrop(imageSize: imageSize, targetAspectRatio: targetAspectRatio).normalizedRect
        let zoom = min(4, max(1, min(base.width / normalizedRect.width, base.height / normalizedRect.height)))
        let horizontal = normalizedRect.width < 1 ? 2 * normalizedRect.minX / (1 - normalizedRect.width) - 1 : 0
        let vertical = normalizedRect.height < 1 ? 2 * normalizedRect.minY / (1 - normalizedRect.height) - 1 : 0
        return Controls(zoom: zoom, offset: CGSize(width: min(1, max(-1, horizontal)), height: min(1, max(-1, vertical))))
    }

    private enum CodingKeys: String, CodingKey { case normalizedRect, usesOriginalRatio }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rect = try values.decode(CGRect.self, forKey: .normalizedRect)
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0, CGRect(x: 0, y: 0, width: 1, height: 1).contains(rect) else {
            throw DecodingError.dataCorruptedError(forKey: .normalizedRect, in: values, debugDescription: "Crop must be inside the picture.")
        }
        normalizedRect = rect
        usesOriginalRatio = try values.decodeIfPresent(Bool.self, forKey: .usesOriginalRatio) ?? false
    }

    /// Whole pixels, contained in the decoded image even at either panning limit.
    func pixelRect(width: Int, height: Int) -> CGRect {
        guard width > 0, height > 0 else { return .zero }
        let pixelWidth = max(1, min(width, Int((normalizedRect.width * CGFloat(width)).rounded())))
        let pixelHeight = max(1, min(height, Int((normalizedRect.height * CGFloat(height)).rounded())))
        let x = max(0, min(width - pixelWidth, Int((normalizedRect.minX * CGFloat(width)).rounded())))
        let y = max(0, min(height - pixelHeight, Int((normalizedRect.minY * CGFloat(height)).rounded())))
        return CGRect(x: x, y: y, width: pixelWidth, height: pixelHeight)
    }
}
