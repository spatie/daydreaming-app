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
