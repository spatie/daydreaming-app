import XCTest
@testable import Daydreaming

final class PromptEditorTests: XCTestCase {
    func testEscapeEndsPictureInstructionEditingBeforeCancellingThePicture() {
        XCTAssertEqual(PictureConfirmationKeyboard.escape(isEditing: true), .endEditing)
        XCTAssertEqual(PictureConfirmationKeyboard.escape(isEditing: false), .cancelPicture)
    }
    func testLegacyInstructionsBecomeReadableWithoutRemovingPersonalInstructions() {
        let legacy = "Keep the street recognizable at {{time}} with {{weather}} on {{date}}. Add Godzilla. Use https://example.com/weather."
        let editable = PromptRenderer.editableText(legacy)
        XCTAssertFalse(editable.contains("{{"))
        XCTAssertTrue(editable.contains("Add Godzilla."))
        XCTAssertTrue(editable.contains("https://example.com/weather"))
        let rendered = PromptRenderer.renderHour(editable, date: Date(timeIntervalSince1970: 0), weather: "rain")
        XCTAssertTrue(rendered.contains("Add Godzilla."))
        XCTAssertTrue(rendered.contains("the weather is rain"))
        XCTAssertTrue(rendered.contains("Preserve the composition and main subjects"))
    }
}
