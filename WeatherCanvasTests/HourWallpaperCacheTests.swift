import XCTest
@testable import Daydreaming

final class HourWallpaperCacheTests: XCTestCase {
    func testUnreadableIndexNeverOverwritesHistoryOrPrunesPurchasedPictures() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = directory.appendingPathComponent("hour-wallpapers.json")
        let unreadable = Data("{broken saved history".utf8)
        try unreadable.write(to: index)
        let old = try picture("purchased.png", in: directory)
        let new = try picture("new.png", in: directory)
        let oldBytes = try Data(contentsOf: old)
        let newBytes = try Data(contentsOf: new)
        var cache = HourWallpaperCache(directory: directory)
        XCTAssertTrue(cache.hasUnreadableIndex)
        XCTAssertThrowsError(try cache.record(pictureID: "picture", recipeID: "recipe", hour: 14,
                                             weather: weather("clear"), url: new))
        XCTAssertThrowsError(try cache.prune(preserving: [], maximumEntries: 0, maximumBytes: 0))
        XCTAssertEqual(try Data(contentsOf: index), unreadable)
        XCTAssertEqual(try Data(contentsOf: old), oldBytes)
        XCTAssertEqual(try Data(contentsOf: new), newBytes)
        XCTAssertTrue(cache.entries.isEmpty)
    }

    func testExplicitCacheClearAllowsNewHistoryAfterUnreadableIndexWasRemoved() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = directory.appendingPathComponent("hour-wallpapers.json")
        try Data("broken history".utf8).write(to: index)
        var cache = HourWallpaperCache(directory: directory)
        try FileManager.default.removeItem(at: index)
        cache.clear()
        let new = try picture("new.png", in: directory)
        try cache.record(pictureID: "picture", recipeID: "recipe", hour: 14, weather: weather("clear"), url: new)
        XCTAssertFalse(cache.hasUnreadableIndex)
        XCTAssertEqual(HourWallpaperCache(directory: directory).entries.map(\.filename), ["new.png"])
    }

    func testCropFramingChangesBothRecipeKeysEvenWhenCroppedPixelsHaveSameDigest() throws {
        var original = CanvasSettings()
        original.sourceDigest = "uniform-identical-pixels"
        var first = original
        first.sourceCrop = PictureCrop(imageSize: CGSize(width: 800, height: 600), targetAspectRatio: 2)
        var moved = original
        moved.sourceCrop = PictureCrop(imageSize: CGSize(width: 800, height: 600), targetAspectRatio: 2,
                                      zoom: 2, offset: CGSize(width: 0.2, height: 0))
        XCTAssertNotEqual(HourWallpaperCache.recipeID(for: first), HourWallpaperCache.recipeID(for: moved))
        XCTAssertNotEqual(HourWallpaperCache.promptRecipeID(for: first), HourWallpaperCache.promptRecipeID(for: moved))
        var originalRatio = original
        originalRatio.sourceCrop = PictureCrop(imageSize: CGSize(width: 800, height: 600), targetAspectRatio: 2,
                                              usesOriginalRatio: true)
        XCTAssertNotEqual(HourWallpaperCache.recipeID(for: first), HourWallpaperCache.recipeID(for: originalRatio))
        XCTAssertEqual(HourWallpaperCache.promptRecipeID(for: try JSONDecoder().decode(CanvasSettings.self, from: JSONEncoder().encode(moved))),
                       HourWallpaperCache.promptRecipeID(for: moved))
    }

    func testSameRecipeHistoryKeepsOlderWallpaperIndexedWhileExactPrefersNewest() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var cache = HourWallpaperCache(directory: directory)
        let older = try picture("used-desktop.png", in: directory)
        let newer = try picture("newer-version.png", in: directory)
        try cache.record(pictureID: "picture", recipeID: "recipe", hour: 16, weather: weather("clear"), url: older)
        try cache.record(pictureID: "picture", recipeID: "recipe", hour: 16, weather: weather("clear"), url: newer)
        XCTAssertEqual(cache.entries.count, 2)
        XCTAssertEqual(cache.exact(pictureID: "picture", recipeID: "recipe", hour: 16, weather: "clear")?.url, newer)
        try cache.record(pictureID: "picture", recipeID: "recipe", hour: 16, weather: weather("clear"), url: newer)
        XCTAssertEqual(cache.entries.count, 2)
        try cache.prune(preserving: [older], maximumEntries: 1)
        XCTAssertEqual(cache.entries.map(\.filename), ["used-desktop.png"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: older.path))
        XCTAssertEqual(HourWallpaperCache(directory: directory).entries, cache.entries)
    }

    func testSavedMetadataIncludesSnapshotAndOldEntriesDecodeWithoutInventingOne() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var cache = HourWallpaperCache(directory: directory)
        var snapshot = CanvasSettings()
        snapshot.promptTemplate = "A recognizable afternoon scene"
        snapshot.legacyCustomPrompt = snapshot.promptTemplate
        snapshot.extraInstructions = snapshot.promptTemplate
        snapshot.sourceDigest = "picture"
        let recipe = HourWallpaperCache.recipeID(for: snapshot)
        let url = try picture("saved.png", in: directory)
        try cache.record(pictureID: "picture", recipeID: recipe, hour: 16, weather: weather("rain"), url: url,
                         renderProfile: .quickPreview, settingsSnapshot: snapshot)
        let restored = try XCTUnwrap(HourWallpaperCache(directory: directory).entries.first)
        XCTAssertEqual(restored.settingsSnapshot, snapshot)
        XCTAssertEqual(HourWallpaperCache.recipeID(for: try XCTUnwrap(restored.settingsSnapshot)), restored.recipeID)
        let entry = try XCTUnwrap(cache.entries.first)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        old.removeValue(forKey: "settingsSnapshot")
        old.removeValue(forKey: "renderProfile")
        let decoded = try JSONDecoder().decode(HourWallpaperCache.Entry.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.settingsSnapshot)
        XCTAssertEqual(decoded.renderProfile, .wallpaper)
        XCTAssertEqual(decoded.filename, "saved.png")
    }

    func testGalleryGroupsByDayAndPromptWithFullQualityFirstAndValidFilesOnly() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var cache = HourWallpaperCache(directory: directory)
        var snapshot = CanvasSettings()
        snapshot.promptTemplate = "One recipe"
        let today = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 14))!
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        for (name, hour, profile, date) in [("full.png", 16, GenerationRenderProfile.wallpaper, today),
                                          ("quick.png", 9, .quickPreview, today), ("older.png", 10, .wallpaper, yesterday)] {
            try cache.record(pictureID: "picture", recipeID: name, hour: hour, weather: weather("clear"),
                             url: picture(name, in: directory), createdAt: date, renderProfile: profile, settingsSnapshot: snapshot)
        }
        let items = cache.entries.compactMap { entry in cache.url(for: entry).map { SavedWallpaperItem(entry: entry, url: $0) } }
        let groups = SavedWallpaperGroup.make(from: items)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.prompt, "One recipe")
        XCTAssertEqual(groups.first?.wallpapers.map(\.entry.filename), ["full.png", "quick.png"])
        XCTAssertGreaterThan(try XCTUnwrap(groups.first?.date), try XCTUnwrap(groups.last?.date))
        try cache.delete(try XCTUnwrap(cache.entries.first))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("full.png").path))
        XCTAssertEqual(HourWallpaperCache(directory: directory).entries.count, 2)
    }

    func testCurrentRecipeUsesExactHourAndWeatherAndPreviousPromptRemainsAvailable() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var cache = HourWallpaperCache(directory: directory)
        let previous = try picture("previous.png", in: directory)
        let current = try picture("current.png", in: directory)
        try cache.record(pictureID: "picture", recipeID: "previous", hour: 14, weather: weather("rain"), url: previous)
        try cache.record(pictureID: "picture", recipeID: "current", hour: 14, weather: weather("clear"), url: current)

        let exact = try XCTUnwrap(cache.preview(pictureID: "picture", recipeID: "current", hour: 14, weather: "clear"))
        XCTAssertEqual(exact.url, current)
        XCTAssertFalse(exact.usesOldRecipe)
        let fallback = try XCTUnwrap(cache.preview(pictureID: "picture", recipeID: "new-prompt", hour: 14, weather: "rain"))
        XCTAssertEqual(fallback.url, previous)
        XCTAssertTrue(fallback.usesOldRecipe)
        XCTAssertNil(cache.preview(pictureID: "different-picture", recipeID: "new-prompt", hour: 14, weather: nil))
        XCTAssertNil(cache.preview(pictureID: "picture", recipeID: "current", hour: 15, weather: "clear"))
        XCTAssertNil(cache.exact(pictureID: "picture", recipeID: "current", hour: 14, weather: "snow"))
        XCTAssertEqual(HourWallpaperCache(directory: directory).entries, cache.entries)
    }

    func testEarlierDaySourceRecipeNeedsUpdateWithoutClaimingPromptChanged() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var cache = HourWallpaperCache(directory: directory)
        var settings = CanvasSettings()
        settings.promptTemplate = "Read https://example.com/daily"
        settings.sourceDigest = "picture"
        let today = Date(timeIntervalSince1970: 1_790_000_000)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let url = try picture("yesterday.png", in: directory)
        try cache.record(pictureID: "picture", recipeID: HourWallpaperCache.recipeID(for: settings, date: yesterday),
                         hour: 14, weather: weather("clear"), url: url,
                         promptRecipeID: HourWallpaperCache.promptRecipeID(for: settings))
        let match = try XCTUnwrap(cache.preview(pictureID: "picture", recipeID: HourWallpaperCache.recipeID(for: settings, date: today),
                                               hour: 14, weather: "clear", promptRecipeID: HourWallpaperCache.promptRecipeID(for: settings)))
        XCTAssertTrue(match.needsUpdate)
        XCTAssertFalse(match.usesOldRecipe)
        settings.promptTemplate = "A different scene"
        let changed = try XCTUnwrap(cache.preview(pictureID: "picture", recipeID: HourWallpaperCache.recipeID(for: settings, date: today),
                                                 hour: 14, weather: "clear", promptRecipeID: HourWallpaperCache.promptRecipeID(for: settings)))
        XCTAssertTrue(changed.needsUpdate)
        XCTAssertTrue(changed.usesOldRecipe)
    }

    func testChangedWeatherShowsSavedPreviewWithoutReusingItAsAnExactMatch() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var cache = HourWallpaperCache(directory: directory)
        let url = try picture("wallpaper.png", in: directory)
        let oldRecipe = try picture("old-recipe.png", in: directory)
        try cache.record(pictureID: "picture", recipeID: "previous", hour: 14, weather: weather("rain"), url: oldRecipe)
        try cache.record(pictureID: "picture", recipeID: "current", hour: 14, weather: weather("clear"), url: url)
        let changed = try XCTUnwrap(cache.preview(pictureID: "picture", recipeID: "current", hour: 14, weather: "rain"))
        XCTAssertEqual(changed.url, url)
        XCTAssertTrue(changed.needsUpdate)
        XCTAssertTrue(changed.weatherChanged)
        XCTAssertFalse(changed.usesOldRecipe)
        XCTAssertNil(cache.exact(pictureID: "picture", recipeID: "current", hour: 14, weather: "rain"))
        try FileManager.default.removeItem(at: url)
        let previous = try XCTUnwrap(cache.preview(pictureID: "picture", recipeID: "current", hour: 14, weather: "rain"))
        XCTAssertEqual(previous.url, oldRecipe)
        XCTAssertTrue(previous.usesOldRecipe)
        try FileManager.default.removeItem(at: oldRecipe)
        XCTAssertNil(cache.preview(pictureID: "picture", recipeID: "current", hour: 14, weather: "clear"))
    }

    func testRecipeChangesForPicturePromptStyleWeatherAndQualityButNotScheduleLimitOrPermission() {
        var original = CanvasSettings()
        original.sourceDigest = "picture-one"
        let recipe = HourWallpaperCache.recipeID(for: original)
        var changed = original
        changed.promptTemplate = "A blue sky"
        XCTAssertNotEqual(recipe, HourWallpaperCache.recipeID(for: changed))
        changed = original; changed.style = .watercolor
        XCTAssertNotEqual(recipe, HourWallpaperCache.recipeID(for: changed))
        changed = original; changed.sourceDigest = "picture-two"
        XCTAssertNotEqual(recipe, HourWallpaperCache.recipeID(for: changed))
        changed = original; changed.weatherChoice = .snow
        XCTAssertNotEqual(recipe, HourWallpaperCache.recipeID(for: changed))
        changed = original; changed.quality = .xhigh
        XCTAssertNotEqual(recipe, HourWallpaperCache.recipeID(for: changed))
        changed = original; changed.model = .fast
        XCTAssertNotEqual(recipe, HourWallpaperCache.recipeID(for: changed))
        changed = original
        changed.interval = .fiveMinutes
        changed.dailyGenerationLimit = 7
        changed.promptFileBookmarks["/a/note.txt"] = Data("granted".utf8)
        XCTAssertEqual(recipe, HourWallpaperCache.recipeID(for: changed))
        XCTAssertNotEqual(HourWallpaperCache.jobID(recipeID: recipe, hour: 14, weather: "clear"),
                          HourWallpaperCache.jobID(recipeID: recipe, hour: 15, weather: "clear"))
    }

    func testDateTokenChangesRecipeAcrossDaysButOrdinaryPromptsReuseHours() {
        let today = Date(timeIntervalSince1970: 1_790_000_000)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        var settings = CanvasSettings()
        XCTAssertEqual(HourWallpaperCache.recipeID(for: settings, date: today), HourWallpaperCache.recipeID(for: settings, date: tomorrow))
        settings.promptTemplate = "Show {{date}} in the sky"
        XCTAssertNotEqual(HourWallpaperCache.recipeID(for: settings, date: today), HourWallpaperCache.recipeID(for: settings, date: tomorrow))
        settings.promptTemplate = "Use https://example.com/daily-news"
        XCTAssertNotEqual(HourWallpaperCache.recipeID(for: settings, date: today), HourWallpaperCache.recipeID(for: settings, date: tomorrow))
        settings.promptTemplate = "Use /tmp/daily-notes.md"
        XCTAssertNotEqual(HourWallpaperCache.recipeID(for: settings, date: today), HourWallpaperCache.recipeID(for: settings, date: tomorrow))
    }

    func testExplicitIntentAloneControlsDesktopAndPaymentAuthorization() {
        var job = applicationJob(priority: .manual)
        XCTAssertFalse(shouldApply(job))
        job.intent = .manualWallpaper
        XCTAssertTrue(shouldApply(job))
        XCTAssertFalse(HourWallpaperApplicationPolicy.shouldApply(job: job, currentRecipeID: "edited", currentHour: 14, automaticUpdates: true))
        XCTAssertFalse(HourWallpaperApplicationPolicy.shouldApply(job: job, currentRecipeID: "recipe", currentHour: 15, automaticUpdates: true))
        job.intent = .automaticWallpaper
        job.userInitiated = false
        XCTAssertTrue(shouldApply(job))
        XCTAssertFalse(HourWallpaperApplicationPolicy.shouldApply(job: job, currentRecipeID: "recipe", currentHour: 14, automaticUpdates: false))
        XCTAssertFalse(HourWallpaperPaymentPolicy.mayStart(job: job, automaticUpdates: false))
        job.intent.insert(.preview)
        job.userInitiated = true
        XCTAssertTrue(HourWallpaperPaymentPolicy.mayStart(job: job, automaticUpdates: false))
    }

    func testPruningPreservesDisplayedAndNewestPicturesAndRemovesOrphans() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var cache = HourWallpaperCache(directory: directory)
        let displayed = try picture("displayed.png", in: directory)
        let discarded = try picture("discarded.png", in: directory)
        let newest = try picture("newest.png", in: directory)
        let orphan = try picture("orphan.png", in: directory)
        for (hour, url) in [displayed, discarded, newest].enumerated() {
            try cache.record(pictureID: "picture", recipeID: "recipe", hour: hour, weather: weather("clear"), url: url)
        }
        try cache.prune(preserving: [displayed, newest], maximumEntries: 2)
        XCTAssertEqual(Set(cache.entries.map(\.filename)), ["displayed.png", "newest.png"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: displayed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: discarded.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    private func shouldApply(_ job: HourlyGenerationJob) -> Bool {
        HourWallpaperApplicationPolicy.shouldApply(job: job, currentRecipeID: "recipe", currentHour: 14, automaticUpdates: true)
    }

    private func applicationJob(priority: HourlyGenerationJob.Priority) -> HourlyGenerationJob {
        HourlyGenerationJob(id: "hour", hour: 14, date: Date(timeIntervalSince1970: 1_000), recipeID: "recipe",
                            weather: weather("clear"), settings: CanvasSettings(), sourcePath: "/fixture/picture.png",
                            priority: priority, requiresCredit: true)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func picture(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("fake cached picture".utf8).write(to: url)
        return url
    }

    private func weather(_ label: String) -> WeatherSnapshot {
        WeatherSnapshot(label: label, symbol: "sun.max", fetchedAt: Date(timeIntervalSince1970: 1_000))
    }
}
