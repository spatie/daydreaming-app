import CoreGraphics
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Daydreaming

final class PictureCropTests: XCTestCase {
    func testImportCopiesSymlinkContentsIntoIndependentSavedOriginal() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.tiff")
        let link = directory.appendingPathComponent("chosen.tiff")
        try writeStripedPicture(to: source, orientation: 1)
        let bytes = try Data(contentsOf: source)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let imported = try ImageStore.importImage(from: link, storageRoot: directory)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: imported.originalURL), bytes)
        XCTAssertFalse(try imported.originalURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? true)
        XCTAssertNotNil(try ImageStore.orientedImage(from: imported.uploadURL))
    }

    func testFailedImportLeavesNoPartialSavedOriginal() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: source)
        XCTAssertThrowsError(try ImageStore.importImage(from: source, storageRoot: directory))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Sources").path).isEmpty)
    }

    func testUnchangedFramingIgnoresRatioLabelAndFloatingPointRounding() {
        let original = PictureCrop(normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1), usesOriginalRatio: true)
        XCTAssertTrue(original.matchesFraming(.original))
        let saved = PictureCrop(normalizedRect: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5))
        let rounded = PictureCrop(normalizedRect: CGRect(x: 0.2000000001, y: 0.2999999999, width: 0.4, height: 0.5), usesOriginalRatio: true)
        XCTAssertTrue(saved.matchesFraming(rounded))
        XCTAssertTrue(saved.matchesFraming(saved.moved(by: CGSize(width: 0.001, height: -0.001))))
        XCTAssertFalse(saved.matchesFraming(saved.moved(by: CGSize(width: 0.01, height: 0))))
        XCTAssertFalse(saved.matchesFraming(saved.scaled(by: 0.9)))
        XCTAssertFalse(saved.matchesFraming(.original))
    }

    func testFrameMovementClampsAtThePictureEdgesWithoutChangingItsSize() {
        let crop = PictureCrop(normalizedRect: CGRect(x: 0.2, y: 0.25, width: 0.4, height: 0.5), usesOriginalRatio: true)
        XCTAssertEqual(crop.moved(by: CGSize(width: -5, height: -5)).normalizedRect,
                       CGRect(x: 0, y: 0, width: 0.4, height: 0.5))
        XCTAssertEqual(crop.moved(by: CGSize(width: 5, height: 5)).normalizedRect,
                       CGRect(x: 0.6, y: 0.5, width: 0.4, height: 0.5))
        XCTAssertTrue(crop.moved(by: CGSize(width: 0.1, height: 0.1)).usesOriginalRatio)
    }

    func testEveryCornerResizePreservesOppositeAnchorAspectAndBounds() {
        for size in [CGSize(width: 3_000, height: 2_000), CGSize(width: 1_000, height: 3_000)] {
            let initial = PictureCrop(imageSize: size, targetAspectRatio: 16.0 / 9, zoom: 2,
                                      offset: CGSize(width: 0.2, height: -0.3))
            for corner in PictureCrop.Corner.allCases {
                for translation in [CGSize(width: -5, height: -5), CGSize(width: -0.1, height: 0.1),
                                    CGSize(width: 0.1, height: -0.1), CGSize(width: 5, height: 5)] {
                    let resized = initial.resized(corner: corner, translation: translation, imageSize: size, targetAspectRatio: 16.0 / 9)
                    let rect = resized.normalizedRect
                    XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(rect))
                    XCTAssertEqual(rect.width * size.width / (rect.height * size.height), 16.0 / 9, accuracy: 0.00001)
                    XCTAssertEqual(corner.isLeft ? rect.maxX : rect.minX,
                                   corner.isLeft ? initial.normalizedRect.maxX : initial.normalizedRect.minX, accuracy: 0.00001)
                    XCTAssertEqual(corner.isTop ? rect.maxY : rect.minY,
                                   corner.isTop ? initial.normalizedRect.maxY : initial.normalizedRect.minY, accuracy: 0.00001)
                }
            }
        }
    }

    func testCropHandleMinimumSizeAndPinchBounds() {
        let size = CGSize(width: 3_000, height: 2_000)
        let crop = PictureCrop(imageSize: size, targetAspectRatio: 16.0 / 9)
        let minimum = CGSize(width: 0.12, height: 0.18)
        let shrunk = crop.resized(corner: .bottomRight, translation: CGSize(width: -10, height: -10),
                                  imageSize: size, targetAspectRatio: 16.0 / 9, minimumSize: minimum)
        XCTAssertGreaterThanOrEqual(shrunk.normalizedRect.width, minimum.width)
        XCTAssertGreaterThanOrEqual(shrunk.normalizedRect.height, minimum.height)
        XCTAssertEqual(shrunk.normalizedRect.width * size.width / (shrunk.normalizedRect.height * size.height), 16.0 / 9, accuracy: 0.00001)
        let expanded = crop.scaled(by: 100)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(expanded.normalizedRect))
        let zoomed = crop.scaled(by: 0.001, minimumSize: minimum)
        XCTAssertGreaterThanOrEqual(zoomed.normalizedRect.width, minimum.width)
        XCTAssertGreaterThanOrEqual(zoomed.normalizedRect.height, minimum.height)
        XCTAssertEqual(crop.scaled(by: .nan), crop)
    }

    func testInteractiveCropKeepsAtLeast120PointsForMovingBetweenTheCornerHandles() {
        let imageSize = CGSize(width: 3_000, height: 2_000)
        let displaySize = CGSize(width: 600, height: 400)
        let minimum = CGSize(width: 120 / displaySize.width, height: 120 / displaySize.height)
        let crop = PictureCrop(imageSize: imageSize, targetAspectRatio: 16.0 / 9)
        let resized = crop.resized(corner: .bottomRight, translation: CGSize(width: -5, height: -5),
                                   imageSize: imageSize, targetAspectRatio: 16.0 / 9, minimumSize: minimum)
        XCTAssertGreaterThanOrEqual(resized.normalizedRect.width * displaySize.width, 120)
        XCTAssertGreaterThanOrEqual(resized.normalizedRect.height * displaySize.height, 120)
        let pinched = crop.scaled(by: 0.001, minimumSize: minimum)
        XCTAssertGreaterThanOrEqual(pinched.normalizedRect.width * displaySize.width, 120)
        XCTAssertGreaterThanOrEqual(pinched.normalizedRect.height * displaySize.height, 120)
    }

    func testAspectChangeRestoresWholeOriginalAndPreservesSavedFraming() {
        let size = CGSize(width: 3_000, height: 2_000)
        let original = PictureCrop(imageSize: size, targetAspectRatio: 1.5, usesOriginalRatio: true)
        XCTAssertEqual(original.normalizedRect, CGRect(x: 0, y: 0, width: 1, height: 1))
        let saved = PictureCrop(imageSize: size, targetAspectRatio: 16.0 / 9, zoom: 2, offset: CGSize(width: 0.6, height: -0.4))
        let restored = saved.constrained(imageSize: size, targetAspectRatio: 16.0 / 9, usesOriginalRatio: false)
        XCTAssertEqual(restored.normalizedRect.minX, saved.normalizedRect.minX, accuracy: 0.00001)
        XCTAssertEqual(restored.normalizedRect.minY, saved.normalizedRect.minY, accuracy: 0.00001)
        XCTAssertEqual(restored.normalizedRect.width, saved.normalizedRect.width, accuracy: 0.00001)
        let changed = saved.constrained(imageSize: size, targetAspectRatio: 1.5, usesOriginalRatio: true)
        XCTAssertTrue(changed.usesOriginalRatio)
        XCTAssertEqual(changed.normalizedRect.midX, saved.normalizedRect.midX, accuracy: 0.00001)
        XCTAssertEqual(changed.normalizedRect.midY, saved.normalizedRect.midY, accuracy: 0.00001)
    }

    func testLandscapeAndPortraitCropMatchScreenRatio() {
        let landscape = PictureCrop(imageSize: CGSize(width: 3_000, height: 2_000), targetAspectRatio: 16.0 / 9)
        XCTAssertEqual(landscape.normalizedRect.width, 1)
        XCTAssertEqual(landscape.normalizedRect.height, 0.84375, accuracy: 0.00001)
        XCTAssertEqual(landscape.normalizedRect.midX, 0.5)
        XCTAssertEqual(landscape.normalizedRect.midY, 0.5)
        let portrait = PictureCrop(imageSize: CGSize(width: 1_000, height: 2_000), targetAspectRatio: 16.0 / 9)
        XCTAssertEqual(portrait.normalizedRect.width, 1)
        XCTAssertEqual(portrait.normalizedRect.height, 0.28125, accuracy: 0.00001)
        XCTAssertEqual(portrait.pixelRect(width: 1_000, height: 2_000).width / portrait.pixelRect(width: 1_000, height: 2_000).height,
                       16.0 / 9, accuracy: 0.002)
    }

    func testZoomAndPanningStayInsideThePictureAtEveryLimit() {
        for size in [CGSize(width: 4_000, height: 2_000), CGSize(width: 1_000, height: 3_000)] {
            for zoom: CGFloat in [0, 1, 2, 4, 100, .infinity, .nan] {
                for offset in [CGSize(width: -99, height: -99), .zero, CGSize(width: 99, height: 99)] {
                    let crop = PictureCrop(imageSize: size, targetAspectRatio: 16.0 / 9, zoom: zoom, offset: offset)
                    XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(crop.normalizedRect))
                    let pixels = crop.pixelRect(width: Int(size.width), height: Int(size.height))
                    XCTAssertTrue(CGRect(origin: .zero, size: size).contains(pixels))
                    XCTAssertGreaterThanOrEqual(pixels.width, 1)
                    XCTAssertGreaterThanOrEqual(pixels.height, 1)
                }
            }
        }
        let zoomed = PictureCrop(imageSize: CGSize(width: 4_000, height: 2_000), targetAspectRatio: 2, zoom: 2,
                                 offset: CGSize(width: 1, height: -1))
        XCTAssertEqual(zoomed.normalizedRect, CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        XCTAssertEqual(PictureCrop.original.pixelRect(width: 400, height: 300), CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    func testInvalidDimensionsFallBackSafely() {
        XCTAssertEqual(PictureCrop(imageSize: .zero, targetAspectRatio: 16.0 / 9), .original)
        XCTAssertEqual(PictureCrop(imageSize: CGSize(width: 100, height: 100), targetAspectRatio: .nan), .original)
        XCTAssertEqual(PictureCrop.original.pixelRect(width: 0, height: 10), .zero)
    }

    func testCropAppliesEXIFOrientationAndRetainsOriginalBytes() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("rotated.tiff")
        try writeStripedPicture(to: sourceURL, orientation: 6)
        let originalBytes = try Data(contentsOf: sourceURL)
        let oriented = try ImageStore.orientedImage(from: sourceURL)
        XCTAssertEqual(oriented.width, 4)
        XCTAssertEqual(oriented.height, 6)
        XCTAssertGreaterThan(try pixel(in: oriented, x: 1, y: 0).red, 200)
        XCTAssertGreaterThan(try pixel(in: oriented, x: 1, y: 5).blue, 200)
        let crop = PictureCrop(imageSize: CGSize(width: 4, height: 6), targetAspectRatio: 1,
                               offset: CGSize(width: 0, height: -1))
        let imported = try ImageStore.cropImage(from: sourceURL, crop: crop, storageRoot: directory)
        let result = try ImageStore.orientedImage(from: imported.originalURL)
        XCTAssertEqual(result.width, 4)
        XCTAssertEqual(result.height, 4)
        XCTAssertGreaterThan(try pixel(in: result, x: 1, y: 0).red, 200)
        XCTAssertGreaterThan(try pixel(in: result, x: 1, y: 3).red, 200)
        XCTAssertEqual(try Data(contentsOf: sourceURL), originalBytes)
        XCTAssertNotEqual(sourceURL, imported.originalURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.uploadURL.path))
        let resultBytes = try Data(contentsOf: imported.originalURL)
        XCTAssertEqual(imported.digest, SHA256.hash(data: resultBytes).map { String(format: "%02x", $0) }.joined())
        XCTAssertNotEqual(imported.digest, SHA256.hash(data: originalBytes).map { String(format: "%02x", $0) }.joined())
        let bottomCrop = PictureCrop(imageSize: CGSize(width: 4, height: 6), targetAspectRatio: 1,
                                     offset: CGSize(width: 0, height: 1))
        let next = try ImageStore.cropImage(from: sourceURL, crop: bottomCrop, storageRoot: directory)
        XCTAssertNotEqual(next.originalURL.deletingLastPathComponent(), imported.originalURL.deletingLastPathComponent())
        XCTAssertNotEqual(next.digest, imported.digest)
        XCTAssertEqual(try Data(contentsOf: sourceURL), originalBytes)
    }

    func testAllEXIFOrientationsAreNormalizedBeforeCropGeometry() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for orientation in 1...8 {
            let source = directory.appendingPathComponent("orientation-\(orientation).tiff")
            try writeStripedPicture(to: source, orientation: orientation)
            let result = try ImageStore.orientedImage(from: source)
            XCTAssertEqual(result.width, orientation >= 5 ? 4 : 6)
            XCTAssertEqual(result.height, orientation >= 5 ? 6 : 4)
            let topLeft = try pixel(in: result, x: 0, y: 0)
            if [1, 4, 5, 6].contains(orientation) {
                XCTAssertGreaterThan(topLeft.red, 200, "Orientation \(orientation)")
            } else {
                XCTAssertGreaterThan(topLeft.blue, 200, "Orientation \(orientation)")
            }
        }
    }

    func testUncroppedPathHasBackwardCompatibleSettingsMigration() throws {
        let previous = try JSONDecoder().decode(CanvasSettings.self, from: Data("{\"sourcePath\":\"/tmp/crop.png\"}".utf8))
        XCTAssertNil(previous.uncroppedSourcePath)
        XCTAssertNil(previous.sourceCrop)
        var current = previous
        current.uncroppedSourcePath = "/tmp/original.jpg"
        current.sourceCrop = PictureCrop(imageSize: CGSize(width: 600, height: 400), targetAspectRatio: 1.5, zoom: 2,
                                         offset: CGSize(width: 0.5, height: -0.25), usesOriginalRatio: true)
        XCTAssertEqual(try JSONDecoder().decode(CanvasSettings.self, from: JSONEncoder().encode(current)).uncroppedSourcePath,
                       current.uncroppedSourcePath)
        XCTAssertEqual(try JSONDecoder().decode(CanvasSettings.self, from: JSONEncoder().encode(current)).sourceCrop, current.sourceCrop)
    }

    func testPersistedCropRestoresZoomPositionAndRatioMode() throws {
        for originalRatio in [false, true] {
            let size = CGSize(width: 3_000, height: 2_000)
            let aspect: CGFloat = originalRatio ? 1.5 : 16.0 / 9
            let initial = PictureCrop(imageSize: size, targetAspectRatio: aspect, zoom: 2.3,
                                      offset: CGSize(width: 0.7, height: -0.4), usesOriginalRatio: originalRatio)
            let saved = try JSONDecoder().decode(PictureCrop.self, from: JSONEncoder().encode(initial))
            let controls = saved.controls(imageSize: size, targetAspectRatio: aspect)
            XCTAssertEqual(controls.zoom, 2.3, accuracy: 0.00001)
            XCTAssertEqual(controls.offset.width, 0.7, accuracy: 0.00001)
            XCTAssertEqual(controls.offset.height, -0.4, accuracy: 0.00001)
            XCTAssertEqual(saved.usesOriginalRatio, originalRatio)
            let restored = PictureCrop(imageSize: size, targetAspectRatio: aspect, zoom: controls.zoom,
                                       offset: controls.offset, usesOriginalRatio: saved.usesOriginalRatio)
            XCTAssertEqual(restored.normalizedRect.minX, saved.normalizedRect.minX, accuracy: 0.00001)
            XCTAssertEqual(restored.normalizedRect.minY, saved.normalizedRect.minY, accuracy: 0.00001)
            XCTAssertEqual(restored.normalizedRect.width, saved.normalizedRect.width, accuracy: 0.00001)
            XCTAssertEqual(restored.normalizedRect.height, saved.normalizedRect.height, accuracy: 0.00001)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeStripedPicture(to url: URL, orientation: Int) throws {
        var bytes: [UInt8] = []
        for _ in 0..<4 {
            for x in 0..<6 { bytes.append(contentsOf: x < 4 ? [255, 0, 0, 255] : [0, 0, 255, 255]) }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(width: 6, height: 4, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 24,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func pixel(in image: CGImage, x: Int, y: Int) throws -> (red: UInt8, blue: UInt8) {
        let pixel = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return (data[0], data[2])
    }
}
