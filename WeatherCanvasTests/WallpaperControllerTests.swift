import AppKit
import XCTest
@testable import Daydreaming

final class WallpaperControllerTests: XCTestCase {
    @MainActor
    func testDesktopOptionsExplicitlyUseProportionalFillWithClipping() {
        let options = WallpaperController.desktopOptions
        XCTAssertEqual((options[.imageScaling] as? NSNumber)?.intValue, NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue).intValue)
        XCTAssertEqual((options[.allowClipping] as? NSNumber)?.boolValue, true)
    }

    func testPortraitPictureFillsLandscapeScreenWithoutStretchingOrEmptyBands() throws {
        let image = CGSize(width: 900, height: 1600)
        let screen = CGSize(width: 1920, height: 1080)
        let rect = try XCTUnwrap(WallpaperController.fillRect(imageSize: image, screenSize: screen))
        XCTAssertEqual(rect.width, screen.width, accuracy: 0.001)
        XCTAssertGreaterThan(rect.height, screen.height)
        XCTAssertEqual(rect.midX, screen.width / 2, accuracy: 0.001)
        XCTAssertEqual(rect.midY, screen.height / 2, accuracy: 0.001)
        XCTAssertEqual(rect.width / rect.height, image.width / image.height, accuracy: 0.001)
    }

    func testLandscapePictureFillsPortraitScreenWithoutStretchingOrEmptyBands() throws {
        let image = CGSize(width: 1600, height: 900)
        let screen = CGSize(width: 900, height: 1600)
        let rect = try XCTUnwrap(WallpaperController.fillRect(imageSize: image, screenSize: screen))
        XCTAssertEqual(rect.height, screen.height, accuracy: 0.001)
        XCTAssertGreaterThan(rect.width, screen.width)
        XCTAssertEqual(rect.midX, screen.width / 2, accuracy: 0.001)
        XCTAssertEqual(rect.midY, screen.height / 2, accuracy: 0.001)
        XCTAssertEqual(rect.width / rect.height, image.width / image.height, accuracy: 0.001)
        XCTAssertNil(WallpaperController.fillRect(imageSize: .zero, screenSize: screen))
    }

    func testMainAndGalleryScreenFramesUseTheExactDesktopFillGeometryForBothOrientations() throws {
        for image in [CGSize(width: 900, height: 1600), CGSize(width: 1600, height: 900)] {
            for viewport in [CGSize(width: 960, height: 380), CGSize(width: 430, height: 320)] {
                let layout = ScreenArtworkLayout(imageSize: image, viewportSize: viewport, displayAspectRatio: 16.0 / 9.0)
                let actual = try XCTUnwrap(layout.imageRect)
                let desktop = try XCTUnwrap(WallpaperController.fillRect(imageSize: image,
                                                                         screenSize: CGSize(width: 1920, height: 1080)))
                let scale = layout.frameSize.width / 1920
                XCTAssertEqual(actual.width, desktop.width * scale, accuracy: 0.001)
                XCTAssertEqual(actual.height, desktop.height * scale, accuracy: 0.001)
                XCTAssertEqual(actual.minX, desktop.minX * scale, accuracy: 0.001)
                XCTAssertEqual(actual.minY, desktop.minY * scale, accuracy: 0.001)
                XCTAssertEqual(layout.frameSize.width / layout.frameSize.height, 16.0 / 9.0, accuracy: 0.001)
                XCTAssertLessThanOrEqual(layout.frameSize.height, viewport.height)
            }
        }
    }
    func testSidebarPreviewShowsIdenticalSourceFramingAtAllApprovedWindowSizes() throws {
        for image in [CGSize(width: 2880, height: 1620), CGSize(width: 900, height: 1600)] {
            let desktop = try XCTUnwrap(WallpaperController.fillRect(imageSize: image, screenSize: CGSize(width: 2560, height: 1440)))
            let expected = CGRect(x: -desktop.minX / desktop.width, y: -desktop.minY / desktop.height,
                                  width: 2560 / desktop.width, height: 1440 / desktop.height)
            for window in [CGSize(width: 760, height: 560), CGSize(width: 900, height: 600), CGSize(width: 1000, height: 720)] {
                let viewport = CGSize(width: window.width - (window.width < 860 ? 240 : 280) - 56,
                                      height: window.height - 220)
                let layout = ScreenArtworkLayout(imageSize: image, viewportSize: viewport, displayAspectRatio: 16.0 / 9.0)
                let rect = try XCTUnwrap(layout.imageRect)
                let actual = CGRect(x: -rect.minX / rect.width, y: -rect.minY / rect.height,
                                    width: layout.frameSize.width / rect.width, height: layout.frameSize.height / rect.height)
                XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.00001)
                XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.00001)
                XCTAssertEqual(actual.width, expected.width, accuracy: 0.00001)
                XCTAssertEqual(actual.height, expected.height, accuracy: 0.00001)
            }
        }
    }

}
