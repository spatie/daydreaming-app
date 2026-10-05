import XCTest
@testable import Daydreaming

final class DaydreamingTests: XCTestCase {
    func testPromptAndCacheAreStableWithinATimeSlot() {
        let morning = date(hour: 10, minute: 5)
        let later = date(hour: 10, minute: 55)
        let first = RenderContext(date: morning, weather: "rainy", intervalMinutes: 60)
        let second = RenderContext(date: later, weather: "rainy", intervalMinutes: 60)
        let settings = CanvasSettings()

        let firstPrompt = PromptRenderer.render(settings.promptTemplate, context: first)
        let secondPrompt = PromptRenderer.render(settings.promptTemplate, context: second)
        XCTAssertEqual(firstPrompt, secondPrompt)
        XCTAssertTrue(firstPrompt.contains("rainy"))

        XCTAssertEqual(
            ImageStore.cacheKey(settings: settings, context: first, renderedPrompt: firstPrompt, size: "2560x1440", forceFresh: false),
            ImageStore.cacheKey(settings: settings, context: second, renderedPrompt: secondPrompt, size: "2560x1440", forceFresh: false)
        )
    }

    func testWeatherAndTimeChangeTheCacheKey() {
        let settings = CanvasSettings()
        let clear = RenderContext(date: date(hour: 10, minute: 5), weather: "clear", intervalMinutes: 60)
        let rain = RenderContext(date: date(hour: 10, minute: 5), weather: "rainy", intervalMinutes: 60)
        let nextHour = RenderContext(date: date(hour: 11, minute: 5), weather: "clear", intervalMinutes: 60)

        func key(_ context: RenderContext) -> String {
            ImageStore.cacheKey(
                settings: settings,
                context: context,
                renderedPrompt: PromptRenderer.render(settings.promptTemplate, context: context),
                size: "2560x1440",
                forceFresh: false
            )
        }

        XCTAssertNotEqual(key(clear), key(rain))
        XCTAssertNotEqual(key(clear), key(nextHour))
    }

    func testCustomPromptStillReceivesTimeAndWeather() {
        let context = RenderContext(date: date(hour: 10, minute: 5), weather: "stormy", intervalMinutes: 30)
        let prompt = PromptRenderer.render("Turn the scene into a watercolor.", context: context)
        XCTAssertTrue(prompt.contains("Turn the scene into a watercolor."))
        XCTAssertTrue(prompt.contains("stormy"))
        XCTAssertTrue(prompt.contains("local time"))
    }

    func testDefaultPromptCanReuseAcrossDays() {
        let settings = CanvasSettings()
        let first = RenderContext(date: date(hour: 10, minute: 5), weather: "rainy", intervalMinutes: 60)
        let nextDay = RenderContext(
            date: Calendar.current.date(byAdding: .day, value: 1, to: date(hour: 10, minute: 5))!,
            weather: "rainy",
            intervalMinutes: 60
        )
        let firstPrompt = PromptRenderer.render(settings.promptTemplate, context: first)
        let secondPrompt = PromptRenderer.render(settings.promptTemplate, context: nextDay)
        XCTAssertEqual(firstPrompt, secondPrompt)
        XCTAssertEqual(
            ImageStore.cacheKey(settings: settings, context: first, renderedPrompt: firstPrompt, size: "2560x1440", forceFresh: false),
            ImageStore.cacheKey(settings: settings, context: nextDay, renderedPrompt: secondPrompt, size: "2560x1440", forceFresh: false)
        )
    }

    func testOlderSettingsDecodeWithoutConnectedSources() throws {
        var settings = CanvasSettings()
        settings.sourcePath = "/some/imported/image.png"
        settings.promptTemplate = "A hand-painted sky"
        settings.interval = .hourly
        let data = try JSONEncoder().encode(settings)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "contextSources")

        let restored = try JSONDecoder().decode(
            CanvasSettings.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(restored.sourcePath, settings.sourcePath)
        XCTAssertEqual(restored.promptTemplate, settings.promptTemplate)
        XCTAssertEqual(restored.interval, .hourly)
        XCTAssertTrue(restored.contextSources.isEmpty)
    }

    private func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: hour, minute: minute))!
    }
}
