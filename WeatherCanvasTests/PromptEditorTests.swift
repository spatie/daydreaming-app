import XCTest
@testable import Daydreaming

final class PromptEditorTests: XCTestCase {
    func testAppearanceIsAddedWithoutChangingTheIdeaTimeOrWeather() {
        let idea = "Preserve the street. Follow the macOS appearance."
        let date = Date(timeIntervalSince1970: 0)
        for appearance in [WallpaperAppearance.light, .dark] {
            let rendered = PromptRenderer.renderHour(idea, date: date, weather: "clear", appearance: appearance)
            XCTAssertTrue(rendered.hasPrefix(idea))
            XCTAssertTrue(rendered.contains("macOS is currently in " + appearance.title))
            XCTAssertTrue(rendered.contains("the weather is clear"))
            XCTAssertTrue(rendered.contains("Keep the requested time and weather accurate"))
            XCTAssertFalse(rendered.contains("storm"))
        }
    }

    func testAppearanceSeparatesCachesAndOldSettingsStillDecode() throws {
        let legacy = try JSONDecoder().decode(CanvasSettings.self, from: Data("{\"promptTemplate\":\"My own idea\"}".utf8))
        XCTAssertNil(legacy.systemAppearance)
        XCTAssertEqual(legacy.promptTemplate, "My own idea")
        var light = legacy
        light.systemAppearance = .light
        var dark = legacy
        dark.systemAppearance = .dark
        XCTAssertNotEqual(HourWallpaperCache.recipeID(for: light), HourWallpaperCache.recipeID(for: dark))
        XCTAssertNotEqual(HourWallpaperCache.promptRecipeID(for: light), HourWallpaperCache.promptRecipeID(for: dark))
        XCTAssertEqual(try JSONDecoder().decode(CanvasSettings.self, from: JSONEncoder().encode(dark)).systemAppearance, .dark)
    }

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
