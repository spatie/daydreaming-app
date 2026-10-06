import XCTest
@testable import Daydreaming

final class WallpaperWindowGeometryBoundaryTests: XCTestCase {
    func testNormalScreenOpensLandscapeEditorInsteadOfPhotoShapedWindow() {
        let size = WallpaperWindowGeometry.initialSize(visibleSize: CGSize(width: 1440, height: 900))
        XCTAssertEqual(size, CGSize(width: 1000, height: 720))
    }

    func testSmallScreenLeavesRoomForTheNativeTitlebar() {
        let screen = CGSize(width: 800, height: 600)
        let size = WallpaperWindowGeometry.initialSize(visibleSize: screen)
        XCTAssertLessThanOrEqual(size.width, screen.width - 32)
        XCTAssertLessThanOrEqual(size.height, screen.height - 80)
        XCTAssertGreaterThanOrEqual(size.width, WallpaperWindowGeometry.minimumSize(visibleSize: screen).width)
    }

    func testEditorMinimumFitsNarrowDisplayInsteadOfOverflowingIt() {
        let minimum = WallpaperWindowGeometry.minimumSize(visibleSize: CGSize(width: 700, height: 550))
        XCTAssertEqual(minimum, CGSize(width: 668, height: 470))
    }
}
