import XCTest
@testable import Daydreaming

final class SavedWallpaperGridNavigationTests: XCTestCase {
    func testTrackpadScrollAccumulatesAndIgnoresMomentum() {
        var policy = SavedVariationScrollPolicy()
        XCTAssertNil(policy.direction(delta: -15, precise: true, momentum: false, began: true, timestamp: 1))
        XCTAssertEqual(policy.direction(delta: -30, precise: true, momentum: false, began: false, timestamp: 1.1), 1)
        XCTAssertNil(policy.direction(delta: -100, precise: true, momentum: true, began: false, timestamp: 1.4))
        XCTAssertNil(policy.direction(delta: -45, precise: true, momentum: false, began: false, timestamp: 1.2))
        XCTAssertEqual(policy.direction(delta: 45, precise: true, momentum: false, began: true, timestamp: 1.4), -1)
        XCTAssertNil(policy.direction(delta: .nan, precise: true, momentum: false, began: false, timestamp: 1.8))
    }

    func testMouseWheelNotchesMoveOneVariationEach() {
        var policy = SavedVariationScrollPolicy()
        XCTAssertEqual(policy.direction(delta: -1, precise: false, momentum: false, began: false, timestamp: 1), 1)
        XCTAssertEqual(policy.direction(delta: 1, precise: false, momentum: false, began: false, timestamp: 1.01), -1)
    }

    func testDockRemainsWhileMainOrSettingsWindowIsOpen() {
        let closingMain = DockPresencePolicy.WindowState(isClosing: true)
        let settings = DockPresencePolicy.WindowState()
        XCTAssertTrue(DockPresencePolicy.showsDock(for: [closingMain, settings]))
        XCTAssertTrue(DockPresencePolicy.showsDock(for: [DockPresencePolicy.WindowState(), .init(isClosing: true)]))
        XCTAssertFalse(DockPresencePolicy.showsDock(for: [closingMain, .init(isClosing: true)]))
        XCTAssertFalse(DockPresencePolicy.showsDock(for: []))
    }

    func testMinimizedWindowKeepsDockButMenuPanelsAndClosedWindowsDoNot() {
        XCTAssertTrue(DockPresencePolicy.showsDock(for: [.init(isVisible: false, isMiniaturized: true)]))
        XCTAssertFalse(DockPresencePolicy.showsDock(for: [.init(isAuxiliary: true)]))
        XCTAssertFalse(DockPresencePolicy.showsDock(for: [.init(isTitled: false)]))
        XCTAssertFalse(DockPresencePolicy.showsDock(for: [.init(isVisible: false)]))
    }
}
