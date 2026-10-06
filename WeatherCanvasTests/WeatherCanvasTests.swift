import XCTest
@testable import Daydreaming

final class DaydreamingTests: XCTestCase {
    func testFrequencyDefaultsAndSavedChoicesSurviveRoundTrip() throws {
        XCTAssertEqual(CanvasSettings().interval, .hourly)
        XCTAssertEqual(try JSONDecoder().decode(CanvasSettings.self, from: Data("{}".utf8)).interval, .hourly)
        let legacy = try JSONDecoder().decode(CanvasSettings.self, from: Data("{\"interval\":\"twiceDaily\"}".utf8))
        XCTAssertEqual(legacy.interval, .twiceDaily)
        for interval in UpdateInterval.allCases {
            var settings = CanvasSettings()
            settings.interval = interval
            settings.customMinutes = 2_880
            let restored = try JSONDecoder().decode(CanvasSettings.self, from: JSONEncoder().encode(settings))
            XCTAssertEqual(restored.interval, interval)
            XCTAssertEqual(restored.customMinutes, 2_880)
        }
    }

    func testCustomFrequencyBoundsAndReadableUnits() {
        var settings = CanvasSettings()
        settings.interval = .custom
        settings.customMinutes = -1
        XCTAssertEqual(settings.intervalMinutes, 1)
        settings.customMinutes = 90
        XCTAssertEqual(settings.frequencyTitle, "Every 90 minutes")
        settings.customMinutes = 120
        XCTAssertEqual(settings.frequencyTitle, "Every 2 hours")
        settings.customMinutes = 20_160
        XCTAssertEqual(settings.frequencyTitle, "Every 2 weeks")
        settings.customMinutes = 100_000
        XCTAssertEqual(settings.intervalMinutes, 43_200)
        for unit in FrequencyUnit.allCases {
            XCTAssertLessThanOrEqual(unit.maximum * unit.minutes, 43_200)
        }
    }

    func testMonthUsesCalendarAcrossShortMonthsAndYearBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Brussels"))
        var settings = CanvasSettings()
        settings.interval = .monthly
        let january = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 14)))
        let february = settings.nextWallpaperDate(after: january, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.month, .day, .hour], from: february),
                       DateComponents(month: 2, day: 28, hour: 14))
        let december = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 12, day: 6, hour: 14)))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day, .hour], from: settings.nextWallpaperDate(after: december, calendar: calendar)),
                       DateComponents(year: 2027, month: 1, day: 6, hour: 14))
    }

    func testWeekPreservesLocalTimeAcrossDaylightSavingChange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Brussels"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 22, hour: 14)))
        var settings = CanvasSettings()
        settings.interval = .weekly
        let next = settings.nextWallpaperDate(after: start, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.month, .day, .hour], from: next), DateComponents(month: 3, day: 29, hour: 14))
        XCTAssertEqual(next.timeIntervalSince(start), 7 * 86_400 - 3_600)
    }

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
            HourWallpaperCache.jobID(recipeID: HourWallpaperCache.recipeID(for: settings, date: first.date), hour: 10, weather: first.weather),
            HourWallpaperCache.jobID(recipeID: HourWallpaperCache.recipeID(for: settings, date: second.date), hour: 10, weather: second.weather)
        )
    }

    func testWeatherAndTimeChangeTheCacheKey() {
        let settings = CanvasSettings()
        let clear = RenderContext(date: date(hour: 10, minute: 5), weather: "clear", intervalMinutes: 60)
        let rain = RenderContext(date: date(hour: 10, minute: 5), weather: "rainy", intervalMinutes: 60)
        let nextHour = RenderContext(date: date(hour: 11, minute: 5), weather: "clear", intervalMinutes: 60)

        func key(_ context: RenderContext) -> String {
            HourWallpaperCache.jobID(recipeID: HourWallpaperCache.recipeID(for: settings, date: context.date),
                                     hour: Calendar.current.component(.hour, from: context.date), weather: context.weather)
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
            HourWallpaperCache.jobID(recipeID: HourWallpaperCache.recipeID(for: settings, date: first.date), hour: 10, weather: first.weather),
            HourWallpaperCache.jobID(recipeID: HourWallpaperCache.recipeID(for: settings, date: nextDay.date), hour: 10, weather: nextDay.weather)
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
        XCTAssertTrue(restored.promptFileBookmarks.isEmpty)
    }

    @MainActor
    func testEmptyPromptRetainsAnEditablePromptAndDropsUnusedBookmarks() {
        let model = AppModel()
        model.savePrompt("A calm blue sky")
        model.settings.promptFileBookmarks["/unused/notes.md"] = Data("fake".utf8)
        model.savePrompt("  \n ")
        XCTAssertEqual(model.settings.promptTemplate, "A calm blue sky")
        XCTAssertTrue(model.settings.promptFileBookmarks.isEmpty)
        model.settings.promptTemplate = ""
        model.savePrompt("")
        XCTAssertEqual(model.settings.promptTemplate, CanvasSettings.defaultPrompt)
    }

    @MainActor
    func testChoosingAnOriginalDuringOnboardingReplacesTheDisplayedOriginal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let builtIn = folder.appendingPathComponent("yosemite.jpg")
        let own = folder.appendingPathComponent("own.jpg")
        try Data().write(to: builtIn)
        try Data().write(to: own)
        let model = AppModel()
        model.adoptImportedPicture(originalURL: builtIn, digest: "builtin")
        model.adoptImportedPicture(originalURL: own, digest: "own")
        XCTAssertEqual(model.sourceImageURL, own)
        XCTAssertEqual(model.displayedImageURL, own)
        model.onboardingComplete = true
        model.adoptImportedPicture(originalURL: builtIn, digest: "builtin")
        XCTAssertEqual(model.displayedImageURL, builtIn)
    }

    private func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: hour, minute: minute))!
    }

    func testPausedSchedulerDoesNotCreateAfterWake() {
        XCTAssertFalse(WallpaperSchedule.shouldCheck(at: date(hour: 10, minute: 0), nextCheck: nil,
                                                     automatic: false, userInitiated: false))
        XCTAssertTrue(WallpaperSchedule.shouldCheck(at: date(hour: 10, minute: 0), nextCheck: nil,
                                                    automatic: false, userInitiated: true))
    }

    func testScheduledCheckStaysPinnedUntilItsBoundary() {
        let nextCheck = date(hour: 12, minute: 0)
        // A prompt, weather, or interval edit must not move this already-planned check.
        XCTAssertFalse(WallpaperSchedule.shouldCheck(at: date(hour: 10, minute: 30), nextCheck: nextCheck,
                                                     automatic: true, userInitiated: false))
        XCTAssertTrue(WallpaperSchedule.shouldCheck(at: nextCheck, nextCheck: nextCheck,
                                                    automatic: true, userInitiated: false))
        XCTAssertTrue(WallpaperSchedule.shouldCheck(at: date(hour: 10, minute: 30), nextCheck: nextCheck,
                                                    automatic: true, userInitiated: true))
    }

    func testNextCheckUsesTheSlotBoundaryNotItsRenderedMidpoint() {
        let context = RenderContext(date: date(hour: 10, minute: 5), weather: "clear", intervalMinutes: 720)
        XCTAssertEqual(context.nextSlotDate, date(hour: 19, minute: 0))
        let custom = RenderContext(date: date(hour: 23, minute: 55), weather: "clear", intervalMinutes: 65)
        XCTAssertEqual(custom.nextSlotDate, Calendar.current.date(byAdding: .day, value: 1, to: date(hour: 0, minute: 0)))
    }

    func testConservativeDefaultDoesNotReplaceSavedSafetyLimit() throws {
        XCTAssertEqual(CanvasSettings().dailyGenerationLimit, 24)
        var saved = CanvasSettings()
        saved.dailyGenerationLimit = 100
        let restored = try JSONDecoder().decode(CanvasSettings.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(restored.dailyGenerationLimit, 100)
    }

    func testShorterIntervalMovesNextCheckToFutureBoundary() {
        let hourly = RenderContext(date: date(hour: 10, minute: 30), weather: "clear", intervalMinutes: 60)
        XCTAssertEqual(WallpaperSchedule.revisedCheck(pinned: date(hour: 19, minute: 0), proposed: hourly.nextSlotDate),
                       date(hour: 11, minute: 0))
        XCTAssertFalse(WallpaperSchedule.shouldCheck(at: date(hour: 10, minute: 30), nextCheck: hourly.nextSlotDate,
                                                     automatic: true, userInitiated: false))
    }

    func testMorningAndEveningScheduleUsesSevenRatherThanMidnightAndNoon() {
        let early = RenderContext(date: date(hour: 2, minute: 0), weather: "clear", intervalMinutes: 720)
        let midday = RenderContext(date: date(hour: 12, minute: 30), weather: "clear", intervalMinutes: 720)
        let night = RenderContext(date: date(hour: 20, minute: 0), weather: "clear", intervalMinutes: 720)
        XCTAssertEqual(early.nextSlotDate, date(hour: 7, minute: 0))
        XCTAssertEqual(midday.slotDate, date(hour: 7, minute: 0))
        XCTAssertEqual(midday.nextSlotDate, date(hour: 19, minute: 0))
        XCTAssertEqual(night.slotDate, date(hour: 19, minute: 0))
        XCTAssertEqual(night.nextSlotDate, Calendar.current.date(byAdding: .day, value: 1, to: date(hour: 7, minute: 0)))
    }

    func testDailyCreationBeforeMorningDoesNotCreateAgainAtSeven() {
        let early = RenderContext(date: date(hour: 6, minute: 30), weather: "rain", intervalMinutes: 1_440)
        let next = Calendar.current.date(byAdding: .day, value: 1, to: date(hour: 7, minute: 0))!
        XCTAssertEqual(early.nextCheckAfterApplying, next)
        // Weather changes cannot bypass the scheduled gate at 7 am.
        XCTAssertFalse(WallpaperSchedule.shouldCheck(at: date(hour: 7, minute: 0), nextCheck: early.nextCheckAfterApplying,
                                                     automatic: true, userInitiated: false))
        XCTAssertTrue(WallpaperSchedule.shouldCheck(at: next, nextCheck: early.nextCheckAfterApplying,
                                                    automatic: true, userInitiated: false))
    }

    func testBeforeDawnStillBelongsToThePreviousEvening() {
        let evening = RenderContext(date: date(hour: 20, minute: 0), weather: "clear", intervalMinutes: 720)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date(hour: 6, minute: 0))!
        let dawn = RenderContext(date: tomorrow, weather: "rain", intervalMinutes: 720)
        XCTAssertEqual(evening.slot, dawn.slot)
        XCTAssertEqual(dawn.nextSlotDate, Calendar.current.date(byAdding: .day, value: 1, to: date(hour: 7, minute: 0)))
    }

    @MainActor
    func testEveryScheduleUsesOnlyTheUserSafetyLimit() {
        let model = AppModel()
        XCTAssertEqual(model.dailyImageLimit, 24)
        for interval in UpdateInterval.allCases {
            model.settings.interval = interval
            XCTAssertEqual(model.settings.interval, interval)
            XCTAssertEqual(model.dailyImageLimit, 24)
        }
        model.settings.customMinutes = 5
        model.settings.interval = .custom
        XCTAssertEqual(model.settings.intervalMinutes, 5)
        model.settings.dailyGenerationLimit = 7
        XCTAssertEqual(model.dailyImageLimit, 7)
        model.settings.dailyGenerationLimit = 0
        XCTAssertEqual(model.dailyImageLimit, 1)
        model.settings.dailyGenerationLimit = 1_000
        XCTAssertEqual(model.dailyImageLimit, 288)
    }

    @MainActor
    func testOnboardingWeatherIsExplicitAndCanBeSkipped() {
        let model = AppModel()
        XCTAssertEqual(model.onboardingLocationState, .notRequested)
        XCTAssertFalse(model.onboardingWeatherReady)
        model.skipOnboardingLocation(choice: .rain)
        XCTAssertTrue(model.onboardingWeatherReady)
        XCTAssertEqual(model.settings.weatherChoice, .rain)
        model.requestOnboardingLocation()
        XCTAssertEqual(model.onboardingLocationState, .allowed)
        XCTAssertEqual(model.settings.weatherChoice, .automatic)
    }

    func testOnboardingReturnsFromDeniedLocationSettings() {
        XCTAssertEqual(OnboardingLocationPolicy.updated(.denied, authorization: .authorized), .allowed)
        XCTAssertEqual(OnboardingLocationPolicy.updated(.requesting, authorization: .denied), .denied)
        XCTAssertEqual(OnboardingLocationPolicy.updated(.notRequested, authorization: .authorized), .notRequested)
    }
}

final class WallpaperStyleTests: XCTestCase {
    func testLegacyCustomPromptKeepsItsTextAndTokenRendering() throws {
        let customPrompt = "  Add falling leaves on {{date}}.\nKeep {{weather}} skies at {{time}}.  "
        let data = try JSONSerialization.data(withJSONObject: ["promptTemplate": customPrompt])
        let restored = try JSONDecoder().decode(CanvasSettings.self, from: data)
        let context = RenderContext(
            date: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10))!,
            weather: "rainy",
            intervalMinutes: 60
        )

        XCTAssertEqual(restored.style, .natural)
        XCTAssertEqual(restored.extraInstructions, customPrompt)
        XCTAssertEqual(restored.legacyCustomPrompt, customPrompt)
        XCTAssertEqual(restored.promptTemplate, customPrompt)
        var unchanged = restored
        unchanged.updateWallpaperInstructions(style: .natural, extraInstructions: customPrompt)
        let roundTrip = try JSONDecoder().decode(CanvasSettings.self, from: JSONEncoder().encode(unchanged))
        XCTAssertEqual(roundTrip.legacyCustomPrompt, customPrompt)
        XCTAssertEqual(roundTrip.promptTemplate, customPrompt)
        XCTAssertEqual(
            PromptRenderer.render(roundTrip.promptTemplate, context: context),
            PromptRenderer.render(customPrompt, context: context)
        )
    }

    func testLegacyBuiltInPromptsBecomeNaturalWithoutExtraInstructions() throws {
        let defaults = [
            "Adjust this image for the time of day and the local weather.",
            "Update my base image for the current time and weather",
            "Preserve the composition, subjects, and style of the original image. Reimagine its lighting and atmosphere for {{time}} with {{weather}} weather. Keep it recognizable as the same scene.",
            CanvasSettings.defaultPrompt,
        ]
        for prompt in defaults {
            let data = try JSONSerialization.data(withJSONObject: ["promptTemplate": prompt])
            let restored = try JSONDecoder().decode(CanvasSettings.self, from: data)
            XCTAssertEqual(restored.style, .natural)
            XCTAssertTrue(restored.extraInstructions.isEmpty)
            XCTAssertNil(restored.legacyCustomPrompt)
            XCTAssertEqual(restored.promptTemplate, CanvasSettings.defaultPrompt)
        }
    }

    func testStyleAndExtraInstructionsSurviveSavingWithoutLosingTokens() throws {
        var settings = CanvasSettings()
        settings.style = .watercolor
        settings.extraInstructions = "Add falling leaves on {{date}}."
        settings.promptTemplate = settings.style.prompt(extraInstructions: settings.extraInstructions)
        let restored = try JSONDecoder().decode(CanvasSettings.self, from: JSONEncoder().encode(settings))

        XCTAssertEqual(restored.style, .watercolor)
        XCTAssertNil(restored.legacyCustomPrompt)
        XCTAssertEqual(restored.extraInstructions, settings.extraInstructions)
        XCTAssertEqual(restored.promptTemplate, settings.promptTemplate)
        XCTAssertTrue(restored.promptTemplate.contains("{{date}}"))
        XCTAssertTrue(restored.style.prompt(extraInstructions: restored.extraInstructions).contains(settings.extraInstructions))
        XCTAssertEqual(WallpaperStyle.natural.prompt(extraInstructions: " \n "), CanvasSettings.defaultPrompt)
    }

    func testNewNaturalInstructionsPreserveThePictureAndReplaceEditedLegacyPrompt() throws {
        let data = try JSONSerialization.data(withJSONObject: ["promptTemplate": "Add snow on {{date}}."])
        var settings = try JSONDecoder().decode(CanvasSettings.self, from: data)
        settings.updateWallpaperInstructions(style: .natural, extraInstructions: "Add falling leaves")

        XCTAssertNil(settings.legacyCustomPrompt)
        XCTAssertTrue(settings.promptTemplate.contains(CanvasSettings.defaultPrompt))
        XCTAssertTrue(settings.promptTemplate.contains("Preserve the composition, main subjects, and style"))
        XCTAssertTrue(settings.promptTemplate.contains("Add falling leaves"))
        let restored = try JSONDecoder().decode(CanvasSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertNil(restored.legacyCustomPrompt)
        XCTAssertEqual(restored.promptTemplate, settings.promptTemplate)
    }

    func testChangingLegacyStyleKeepsOptionalTextAndRemovesVerbatimOverride() throws {
        let original = "Add snow on {{date}}."
        let data = try JSONSerialization.data(withJSONObject: ["promptTemplate": original])
        var settings = try JSONDecoder().decode(CanvasSettings.self, from: data)
        settings.updateWallpaperInstructions(style: .cinematic, extraInstructions: original)

        XCTAssertNil(settings.legacyCustomPrompt)
        XCTAssertTrue(settings.promptTemplate.contains("cinematic lighting"))
        XCTAssertTrue(settings.promptTemplate.contains(original))
    }
}

final class WallpaperWindowGeometryTests: XCTestCase {
    func testLargeDisplayDoesNotTurnUtilityIntoFullscreenCanvas() {
        let size = WallpaperWindowGeometry.initialSize(visibleSize: CGSize(width: 2560, height: 1440))
        XCTAssertEqual(size, CGSize(width: 1000, height: 720))
    }
}
