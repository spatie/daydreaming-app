import XCTest
@testable import Daydreaming

final class SliderInteractionPolicyTests: XCTestCase {
    func testDraggingAndReleasingDoNotRequestPaidCreation() {
        XCTAssertFalse(SliderInteractionPolicy.shouldEnqueue(isDragging: true, userRequested: false))
        XCTAssertFalse(SliderInteractionPolicy.shouldEnqueue(isDragging: false, userRequested: false))
        XCTAssertFalse(SliderInteractionPolicy.shouldEnqueue(isDragging: true, userRequested: true))
        XCTAssertTrue(SliderInteractionPolicy.shouldEnqueue(isDragging: false, userRequested: true))
    }

    func testRequestedHoursStayWithinTheDayAndRoundToWholeHours() {
        XCTAssertEqual(SliderInteractionPolicy.clampedHour(-5), 0)
        XCTAssertEqual(SliderInteractionPolicy.clampedHour(24), 23)
        XCTAssertEqual(SliderInteractionPolicy.clampedHour(10.4), 10)
        XCTAssertEqual(SliderInteractionPolicy.clampedHour(10.6), 11)
        XCTAssertEqual(SliderInteractionPolicy.clampedHour(.nan), 0)
        XCTAssertEqual(SliderInteractionPolicy.clampedHour(.infinity), 0)
    }
}

@MainActor
final class SettingsNavigationTests: XCTestCase {
    func testTargetedRecoveryStartsOnRequestedPane() {
        let navigation = SettingsNavigation(pane: .imageAI)
        XCTAssertEqual(navigation.pane, .imageAI)
        navigation.goBack()
        navigation.goForward()
        XCTAssertEqual(navigation.pane, .imageAI)
    }

    func testBackThenSelectingNewPaneReplacesForwardHistory() {
        let navigation = SettingsNavigation(pane: .general)
        navigation.select(.imageAI)
        navigation.select(.storage)
        navigation.goBack()
        XCTAssertEqual(navigation.pane, .imageAI)
        navigation.select(.wallpapers)
        XCTAssertFalse(navigation.canGoForward)
        navigation.goBack()
        XCTAssertEqual(navigation.pane, .imageAI)
        navigation.goForward()
        XCTAssertEqual(navigation.pane, .wallpapers)
    }
}
